"""Yüz tanıma modelini Core ML'e çevirir ve eşitliğini doğrular.

Aday: FaceNet InceptionResnetV1 (facenet-pytorch, VGGFace2 ağırlıkları, MIT kod lisansı).
Ağırlıklar kütüphanenin barındırdığı URL'den iner; indirilen dosyanın SHA-256'sı
sabitleme için yazdırılır. Çıktı: build/Model.mlpackage (mlprogram, FP16, macOS 14+).

Dönüşüm yolu: torch.export → run_decompositions → coremltools (trace yolu torch 2.14 +
coremltools 9'da InceptionResnetV1'i çeviremiyor; export yolu çalışıyor).
Eşitlik kapısı: 100 rastgele girdide torch ile Core ML kosinüsü >= 0.999 (yoksa çıkış 1).
"""
import hashlib
import pathlib
import sys
import warnings

warnings.filterwarnings("ignore")

import numpy as np
import torch
import coremltools as ct
from facenet_pytorch import InceptionResnetV1

REPO = pathlib.Path(__file__).resolve().parents[2]
OUT = REPO / "build" / "Model.mlpackage"
INPUT_SIZE = 160
EMBED_DIM = 512


def weight_sha256() -> str:
    cache = pathlib.Path.home() / ".cache" / "torch" / "checkpoints"
    for p in sorted(cache.glob("*vggface2*.pt")):
        return hashlib.sha256(p.read_bytes()).hexdigest()
    return "(ağırlık önbellekte bulunamadı)"


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    model = InceptionResnetV1(pretrained="vggface2").eval()

    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
    exported = torch.export.export(model, (example,)).run_decompositions({})
    mlmodel = ct.convert(
        exported,
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
    )

    # Giriş/çıkış adlarını sabit API'ye çevir: input / embedding.
    spec = mlmodel.get_spec()
    in_name = spec.description.input[0].name
    out_name = spec.description.output[0].name
    if in_name != "input":
        ct.utils.rename_feature(spec, in_name, "input")
    if out_name != "embedding":
        ct.utils.rename_feature(spec, out_name, "embedding")
    mlmodel = ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)
    mlmodel.save(str(OUT))

    worst = 1.0
    for _ in range(100):
        x = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
        with torch.no_grad():
            ref = model(x).numpy().reshape(-1)
        got = np.array(mlmodel.predict({"input": x.numpy()})["embedding"]).reshape(-1)
        ref /= np.linalg.norm(ref)
        got /= np.linalg.norm(got)
        worst = min(worst, float((ref * got).sum()))

    print(f"torch {torch.__version__} coremltools {ct.__version__}")
    print(f"weights SHA-256: {weight_sha256()}")
    print(f"embedding dim: {EMBED_DIM}, input: {INPUT_SIZE}x{INPUT_SIZE}, I/O: input→embedding")
    print(f"parity (worst cosine over 100): {worst:.6f}")
    if worst < 0.999:
        print("EŞİTLİK BAŞARISIZ (< 0.999)", file=sys.stderr)
        return 1
    print(f"OK → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
