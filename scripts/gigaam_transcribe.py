#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gigaam_transcribe.py — распознавание WAV (16 кГц, моно) моделью GigaAM v3 E2E-RNN-T.

Вызывается из transcribe.sh интерпретатором из venv (…/Transcribe/gigaam/venv):

    python gigaam_transcribe.py --wav in.wav --out /tmp/base [--srt]
                                [--device auto|mps|cpu] [--model v3_e2e_rnnt]
                                [--models-dir DIR] [--batch-size N]

Пишет:
    <out>.txt  — расшифровка, одна реплика (VAD-чанк) в строке;
    <out>.srt  — (с --srt) те же реплики с таймкодами — для TIMESTAMPS=1 / READABLE=1;
    <out>.meta — device=…, chunks=…, model=… (для шапки результата).
В stdout печатает строки «progress = NN%» — их ловит пингер уведомлений в transcribe.sh.

Почему своя нарезка: у GigaAM .transcribe() принимает аудио только до 25 с, а штатный
.transcribe_longform() требует pyannote.audio и токен Hugging Face. Здесь речь режется
Silero VAD (веса лежат внутри pip-пакета, токен не нужен) на чанки ≤ 22 с и распознаётся
пачками — та же схема, что внутри transcribe_longform, но без внешних зависимостей.
"""
import argparse
import logging
import math
import os
import re
import sys
import time

# Неподдержанные MPS-операции исполнять на CPU, а не падать (нужно до import torch).
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import torch  # noqa: E402

SR = 16000
MAX_CHUNK_S = 22.0   # как в gigaam.vad_utils.segment_audio_file
MIN_CHUNK_S = 15.0   # чанк «достаточно длинный» — можно закрывать
HARD_LIMIT_S = 25.0  # порог .transcribe(); длиннее — режем поровну
DEFAULT_MODEL = "v3_e2e_rnnt"


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def progress(pct):
    print("progress = %d%%" % int(pct), flush=True)


# --- Аудио -------------------------------------------------------------------
def load_wav(path):
    data, sr = sf.read(path, dtype="float32", always_2d=True)
    mono = data.mean(axis=1) if data.shape[1] > 1 else data[:, 0]
    wav = torch.from_numpy(np.ascontiguousarray(mono))
    if sr != SR:
        import torchaudio
        wav = torchaudio.functional.resample(wav, sr, SR)
    return wav.contiguous()


# --- Нарезка на чанки --------------------------------------------------------
def speech_regions(wav):
    """[(start_s, end_s), …] речевых участков по Silero VAD. None — VAD недоступен."""
    threads = torch.get_num_threads()
    try:
        # ВАЖНО: импорт silero_vad делает torch.set_num_threads(1) — возвращаем потоки ниже.
        from silero_vad import get_speech_timestamps, load_silero_vad
        vad = load_silero_vad()
        stamps = get_speech_timestamps(
            wav, vad, sampling_rate=SR, threshold=0.5,
            min_speech_duration_ms=250, min_silence_duration_ms=300,
            speech_pad_ms=150, max_speech_duration_s=MAX_CHUNK_S,
        )
    except Exception as exc:  # noqa: BLE001
        log("silero-vad недоступен (%r) — режу окнами по %.0f с" % (exc, MAX_CHUNK_S))
        return None
    finally:
        torch.set_num_threads(max(threads, os.cpu_count() or 1))
    return [(t["start"] / SR, t["end"] / SR) for t in stamps]


def merge_regions(regions):
    """Склеиваем речевые участки в чанки: охват ≤ MAX_CHUNK_S, по возможности ≥ MIN_CHUNK_S."""
    chunks = []
    cur_start = cur_end = None
    for start, end in regions:
        if cur_start is None:
            cur_start, cur_end = start, end
            continue
        if (end - cur_start) > MAX_CHUNK_S or (cur_end - cur_start) > MIN_CHUNK_S:
            chunks.append((cur_start, cur_end))
            cur_start = start
        cur_end = end
    if cur_start is not None:
        chunks.append((cur_start, cur_end))

    out = []  # страховка: чанк длиннее HARD_LIMIT_S делим поровну
    for start, end in chunks:
        parts = math.ceil((end - start) / MAX_CHUNK_S) if (end - start) > HARD_LIMIT_S else 1
        step = (end - start) / parts
        out.extend((start + i * step, start + (i + 1) * step) for i in range(parts))
    return out


def fixed_windows(total_s):
    n = max(1, math.ceil(total_s / MAX_CHUNK_S))
    step = total_s / n
    return [(i * step, (i + 1) * step) for i in range(n)]


# --- Модель ------------------------------------------------------------------
def pick_device(arg):
    if arg == "auto":
        return "mps" if torch.backends.mps.is_available() else "cpu"
    return arg


def load_model(name, device, models_dir, fp16):
    import gigaam
    logging.getLogger().setLevel(logging.WARNING)
    os.makedirs(models_dir, exist_ok=True)
    return gigaam.load_model(name, device=device, download_root=models_dir, fp16_encoder=fp16)


def decode(model, encoded, encoded_len, wav_lens):
    """Список текстов для батча. Основной путь — как в GigaAMASR.transcribe_longform."""
    if hasattr(model, "_decode"):
        return [text for text, _ in model._decode(encoded, encoded_len, wav_lens, False)]
    return [item[0] for item in model.decoding.decode(model.head, encoded, encoded_len)]


def transcribe_chunks(model, wav, chunks, batch_size):
    device, dtype = model._device, model._dtype
    # По длине — меньше паддинга в батче; результат раскладываем обратно по индексам.
    order = sorted(range(len(chunks)), key=lambda i: chunks[i][1] - chunks[i][0])
    texts = [""] * len(chunks)
    done = 0
    for b in range(0, len(order), batch_size):
        idxs = order[b:b + batch_size]
        segs = [wav[int(chunks[i][0] * SR):int(chunks[i][1] * SR)] for i in idxs]
        lens = torch.tensor([s.numel() for s in segs])
        pad = torch.nn.utils.rnn.pad_sequence(segs, batch_first=True)
        with torch.inference_mode():
            enc, enc_len = model.forward(pad.to(device).to(dtype), lens.to(device))
            batch_texts = decode(model, enc, enc_len, lens.to(device))
        for i, text in zip(idxs, batch_texts):
            texts[i] = " ".join(text.split())
        done += len(idxs)
        progress(100.0 * done / len(chunks))
    return texts


# --- Склейка фраз, разорванных границей чанка --------------------------------
# Нарезка по VAD режет речь по паузам ≥ 100 мс, и предложение часто попадает в два
# чанка; модель каждый чанк начинает с заглавной, а иногда — с «...». Если предыдущий
# чанк не закончен знаком .!? и пауза до следующего короткая — это продолжение:
# убираем ведущее многоточие и заглавную, а в .txt пишем в одну строку.
def is_finished(text):
    tail = text.rstrip("»\")' ")
    return tail.endswith((".", "!", "?")) and not tail.endswith("...")


def heal_boundaries(chunks, texts, max_gap=1.5):
    """[(chunk, text, is_continuation), …] — пустые чанки выбрасываются."""
    items, prev_text, prev_end = [], None, None
    for (start, end), text in zip(chunks, texts):
        if not text:
            continue
        cont = False
        if prev_text is not None and (start - prev_end) <= max_gap and not is_finished(prev_text):
            text = re.sub(r"^(?:\.{2,}|…)\s*", "", text)
            first = text.split()[0] if text.split() else ""
            # Заглавную снимаем, если это не аббревиатура вроде «НСИ»/«CRM».
            if first[:1].isupper() and not first[1:2].isupper():
                text = text[0].lower() + text[1:]
            cont = True
        if text:
            items.append(((start, end), text, cont))
            prev_text, prev_end = text, end
    return items


# --- Вывод -------------------------------------------------------------------
def srt_time(sec):
    ms = int(round(sec * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


def write_outputs(out, items, want_srt, meta):
    lines = []
    for _, text, cont in items:
        if cont and lines:
            lines[-1] += " " + text
        else:
            lines.append(text)
    with open(out + ".txt", "w", encoding="utf-8") as f:
        for text in lines:
            f.write(text + "\n")
    if want_srt:  # в .srt чанки остаются отдельными репликами — точные таймкоды важнее
        with open(out + ".srt", "w", encoding="utf-8") as f:
            for n, ((start, end), text, _) in enumerate(items, 1):
                f.write("%d\n%s --> %s\n%s\n\n" % (n, srt_time(start), srt_time(end), text))
    with open(out + ".meta", "w", encoding="utf-8") as f:
        for k, v in meta.items():
            f.write("%s=%s\n" % (k, v))


# --- main --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wav", required=True, help="WAV 16 кГц моно (из ffmpeg)")
    ap.add_argument("--out", required=True, help="база имени выходных файлов (без расширения)")
    ap.add_argument("--srt", action="store_true", help="дополнительно писать <out>.srt")
    ap.add_argument("--device", default="auto", choices=["auto", "mps", "cpu"])
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--models-dir", default=os.path.expanduser("~/.cache/gigaam"))
    ap.add_argument("--batch-size", type=int, default=4)
    ap.add_argument("--fp16", action="store_true", help="fp16-энкодер на GPU (по умолчанию fp32)")
    ap.add_argument("--no-heal", action="store_true", help="не склеивать фразы, разорванные границей чанка")
    args = ap.parse_args()

    t0 = time.time()
    wav = load_wav(args.wav)
    total_s = wav.numel() / SR

    regions = speech_regions(wav)
    if regions is None:
        chunks, vad_kind = fixed_windows(total_s), "windows"
    else:
        chunks, vad_kind = merge_regions(regions), "silero"
    log("аудио %.1f с → %d чанков (%s), VAD %.1f с" % (total_s, len(chunks), vad_kind, time.time() - t0))

    device = pick_device(args.device)
    if not chunks:
        log("речь не найдена — пустой результат")
        write_outputs(args.out, [], args.srt, {"device": device, "chunks": 0, "model": args.model, "vad": vad_kind})
        progress(100)
        return 0

    t1 = time.time()
    try:
        model = load_model(args.model, device, args.models_dir, args.fp16 and device != "cpu")
        log("модель %s загружена на %s за %.1f с" % (args.model, device, time.time() - t1))
        texts = transcribe_chunks(model, wav, chunks, args.batch_size)
    except Exception as exc:  # noqa: BLE001
        if device == "cpu" or args.device != "auto":
            raise
        log("%s не сработал (%r) — повторяю на CPU" % (device, exc))
        device = "cpu"
        model = load_model(args.model, device, args.models_dir, False)
        texts = transcribe_chunks(model, wav, chunks, args.batch_size)

    elapsed = time.time() - t0
    if args.no_heal:
        items = [(c, t, False) for c, t in zip(chunks, texts) if t]
    else:
        items = heal_boundaries(chunks, texts)
    healed = sum(1 for _, _, cont in items if cont)
    write_outputs(args.out, items, args.srt,
                  {"device": device, "chunks": len(chunks), "model": args.model, "vad": vad_kind,
                   "healed": healed, "elapsed": "%.1f" % elapsed})
    log("склеено разорванных фраз: %d" % healed)
    log("готово: %d чанков за %.1f с (%.1fx realtime)" % (len(chunks), elapsed, total_s / max(elapsed, 1e-6)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        log("ОШИБКА GigaAM: %r" % (exc,))
        sys.exit(1)
