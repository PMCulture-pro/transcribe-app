#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
diarize.py — кто когда говорил: разметка WAV (16 кГц, моно) по спикерам, полностью офлайн.

Вызывается из transcribe.sh интерпретатором из venv (…/Transcribe/gigaam/venv):

    python diarize.py --wav in.wav --out turns.tsv --models-dir DIR [--speakers auto|N]

Пишет <out>: строки «начало<TAB>конец<TAB>номер_спикера» (секунды, спикеры с 1 — в порядке
первого появления в записи). В stdout — «progress = NN%» для пингера уведомлений.

Модели — те же, что внутри pyannote/speaker-diarization-3.1, но в ONNX через sherpa-onnx
(без pyannote.audio и без токена Hugging Face):
  • сегментация pyannote segmentation-3.0 — где речь и где меняется голос;
  • эмбеддинги голоса WeSpeaker ResNet34-LM (VoxCeleb) — чей это голос;
  • кластеризация: заданное число спикеров (--speakers N) или порог сходства (auto).
"""
import argparse
import os
import sys

SR = 16000
SEG_MODEL = "segmentation-3.0.onnx"
EMB_MODEL = "wespeaker_en_voxceleb_resnet34_LM.onnx"
# Порог кластеризации для auto: косинусное расстояние, выше — меньше спикеров. 0.5 — умолчание
# sherpa-onnx; для WeSpeaker на совещаниях лучше чуть строже, иначе один голос дробится.
AUTO_THRESHOLD = 0.6


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_wav(path):
    import numpy as np
    import soundfile as sf
    data, sr = sf.read(path, dtype="float32", always_2d=True)
    mono = data.mean(axis=1) if data.shape[1] > 1 else data[:, 0]
    if sr != SR:
        raise SystemExit("ожидается WAV %d Гц, получено %d" % (SR, sr))
    return np.ascontiguousarray(mono)


def diarize(audio, models_dir, speakers, threshold):
    import sherpa_onnx
    seg = os.path.join(models_dir, SEG_MODEL)
    emb = os.path.join(models_dir, EMB_MODEL)
    for p in (seg, emb):
        if not os.path.isfile(p):
            raise SystemExit("нет модели диаризации: %s (переустановите с WITH_GIGAAM=1)" % p)
    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=seg),
            num_threads=max(1, (os.cpu_count() or 2) // 2),
        ),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=emb, num_threads=max(1, (os.cpu_count() or 2) // 2)),
        clustering=sherpa_onnx.FastClusteringConfig(num_clusters=speakers, threshold=threshold),
        min_duration_on=0.3,   # короче — шум, а не реплика
        min_duration_off=0.5,  # паузы короче не разрывают реплику одного спикера
    )
    if not config.validate():
        raise SystemExit("неверная конфигурация sherpa-onnx")
    sd = sherpa_onnx.OfflineSpeakerDiarization(config)

    last = [-1]

    def on_progress(done, total):
        pct = int(100 * done / max(total, 1))
        if pct // 5 != last[0] // 5:
            print("progress = %d%%" % pct, flush=True)
            last[0] = pct
        return 0

    result = sd.process(audio, callback=on_progress).sort_by_start_time()
    return [(r.start, r.end, r.speaker) for r in result]


def renumber(turns):
    """Спикеры 1, 2, 3… в порядке первого появления (кластеры sherpa нумеруются произвольно)."""
    order = {}
    out = []
    for start, end, spk in turns:
        if spk not in order:
            order[spk] = len(order) + 1
        out.append((start, end, order[spk]))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wav", required=True, help="WAV 16 кГц моно (из ffmpeg)")
    ap.add_argument("--out", required=True, help="файл результата (TSV: начало, конец, спикер)")
    ap.add_argument("--models-dir", required=True)
    ap.add_argument("--speakers", default="auto", help="auto или точное число спикеров")
    ap.add_argument("--threshold", type=float, default=AUTO_THRESHOLD, help="порог для auto")
    args = ap.parse_args()

    n = -1
    if args.speakers not in ("", "auto", "1"):
        try:
            n = int(args.speakers)
        except ValueError:
            log("SPEAKERS=%r не число — использую auto" % args.speakers)
        if n < 2:
            n = -1
    audio = load_wav(args.wav)
    turns = renumber(diarize(audio, args.models_dir, n, args.threshold))
    with open(args.out, "w", encoding="utf-8") as f:
        for start, end, spk in turns:
            f.write("%.2f\t%.2f\t%d\n" % (start, end, spk))
    log("диаризация: %d реплик, спикеров: %d" % (len(turns), len({t[2] for t in turns})))
    print("progress = 100%", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        log("ОШИБКА диаризации: %r" % (exc,))
        sys.exit(1)
