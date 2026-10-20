# Probe: coremltools conversion toolchain works on this Mac (PyTorch -> .mlpackage, FP16).
import numpy as np
import torch
import coremltools as ct


class TinyEmbedder(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.conv = torch.nn.Conv2d(3, 8, 3, padding=1)
        self.fc = torch.nn.Linear(8 * 112 * 112, 128)

    def forward(self, x):
        y = torch.relu(self.conv(x))
        y = self.fc(y.flatten(1))
        return torch.nn.functional.normalize(y, dim=1)


model = TinyEmbedder().eval()
x = torch.rand(1, 3, 112, 112)
traced = torch.jit.trace(model, x)
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input", shape=x.shape)],
    outputs=[ct.TensorType(name="embedding")],
    minimum_deployment_target=ct.target.macOS14,
    compute_precision=ct.precision.FLOAT16,
)
mlmodel.save("Probe.mlpackage")

reference = model(x).detach().numpy()
np.save("x.npy", x.numpy())
np.save("ref.npy", reference)
out = mlmodel.predict({"input": x.numpy()})["embedding"]
cos = float((out * reference).sum() / (np.linalg.norm(out) * np.linalg.norm(reference)))
print("torch", torch.__version__, "coremltools", ct.__version__)
print("CoreML(python) vs torch cosine:", round(cos, 6))
