#!/usr/bin/env python3
"""
Convert a *pre-trained* PyTorch tomato-disease model to Core ML (no training needed).

The coursework allows pre-trained models "converted to Core ML format". A public candidate (I could NOT download or
verify it from my sandbox – the weights are on Google Drive): the README of
  https://github.com/shywel/DeepLearning_PlantDiseases   (also bucharestai/DeepLearning_PlantDiseases)
links "pretrained models on 10 classes of Tomato from PlantVillage dataset: AlexNet or VGG13".

Steps
  1. Download the tomato AlexNet or VGG13 file from the links in that README.
  2. pip install torch torchvision coremltools pillow
  3. python ml/convert_pretrained_pytorch.py --weights path/to/model.pth --arch alexnet --check
       --check runs the 10 bundled PlantVillage sample leaves through the PyTorch model FIRST and prints the accuracy,
       so you can confirm the class order / normalisation before converting. Aim for >= 8/10 correct.
  4. If the check passes, the script writes ml/AgriNovaLeaf.mlpackage -> copy it to AgriNova/Resources/Models/.

If the accuracy is poor, try `--order` variants printed by the script, or fall back to training (docs/ML_MODEL_GUIDE.md).
"""
import argparse, glob, os, sys
import torch, torch.nn as nn
from torchvision import models, transforms
from PIL import Image

# Alphabetical folder order == torchvision ImageFolder order == what most training scripts use.
CLASSES = ["Tomato___Bacterial_spot", "Tomato___Early_blight", "Tomato___Late_blight", "Tomato___Leaf_Mold",
           "Tomato___Septoria_leaf_spot", "Tomato___Spider_mites Two-spotted_spider_mite", "Tomato___Target_Spot",
           "Tomato___Tomato_Yellow_Leaf_Curl_Virus", "Tomato___Tomato_mosaic_virus", "Tomato___healthy"]
KEYS = ["bacterial_spot", "early_blight", "late_blight", "leaf_mold", "septoria", "spider_mites", "target_spot",
        "yellow_leaf_curl", "mosaic", "healthy"]
SAMPLES = os.path.join(os.path.dirname(__file__), "..", "AgriNova", "Resources", "SampleLeaves")

ap = argparse.ArgumentParser()
ap.add_argument("--weights", required=True)
ap.add_argument("--arch", choices=["alexnet", "vgg13", "auto"], default="auto", help="needed only if the file is a state_dict")
ap.add_argument("--size", type=int, default=224)
ap.add_argument("--check", action="store_true")
args = ap.parse_args()

obj = torch.load(args.weights, map_location="cpu", weights_only=False)
if isinstance(obj, nn.Module):
    net = obj
else:
    state = obj.get("state_dict", obj) if isinstance(obj, dict) else obj
    arch = args.arch if args.arch != "auto" else ("vgg13" if any("features.20" in k for k in state) else "alexnet")
    net = getattr(models, arch)(weights=None, num_classes=len(CLASSES))
    net.load_state_dict({k.replace("module.", ""): v for k, v in state.items()})
net.eval()

MEAN, STD = [0.485, 0.456, 0.406], [0.229, 0.224, 0.225]
prep = transforms.Compose([transforms.Resize((args.size, args.size)), transforms.ToTensor(), transforms.Normalize(MEAN, STD)])

if args.check:
    ok = total = 0
    for idx, key in enumerate(KEYS):
        for f in sorted(glob.glob(os.path.join(SAMPLES, f"sample_{key}_*.jpg"))):
            with torch.no_grad():
                pred = net(prep(Image.open(f).convert("RGB")).unsqueeze(0)).argmax(1).item()
            total += 1; ok += int(pred == idx)
            print(f"{os.path.basename(f):38s} expected {idx} predicted {pred} {'OK' if pred == idx else 'X'}")
    print(f"\nsample accuracy {ok}/{total}")
    if ok / max(1, total) < 0.7:
        sys.exit("Accuracy too low – class order or normalisation differs. Not converting.")

import coremltools as ct

class Wrap(nn.Module):
    """Normalisation + softmax inside the model so Vision only has to supply a 0-1 RGB image."""
    def __init__(self, m):
        super().__init__()
        self.m = m
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))
    def forward(self, x):
        return torch.softmax(self.m((x - self.mean) / self.std), dim=1)

wrapped = Wrap(net).eval()
traced = torch.jit.trace(wrapped, torch.rand(1, 3, args.size, args.size))
mlmodel = ct.convert(traced,
    inputs=[ct.ImageType(name="image", shape=(1, 3, args.size, args.size), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
    classifier_config=ct.ClassifierConfig(CLASSES), minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram")
mlmodel.short_description = "AgriNova tomato leaf disease classifier (converted pre-trained PlantVillage model)"
out = os.path.join(os.path.dirname(__file__), "AgriNovaLeaf.mlpackage")
mlmodel.save(out); print("saved", out)
