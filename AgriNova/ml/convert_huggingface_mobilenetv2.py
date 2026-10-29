#!/usr/bin/env python3
"""
Convert a REAL, already-trained MobileNetV2 plant-disease model to Core ML – no training required.

Model (verified to exist on Hugging Face):  linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification
  - google/mobilenet_v2_1.0_224 fine-tuned on the PlantVillage dataset (38 classes incl. 10 tomato classes)
  - reported evaluation accuracy 95.4 %   - licence field on the model card: "other"  → cite it in your report
  https://huggingface.co/linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification

Run on a Mac (or Colab) with internet:
  pip install torch torchvision transformers coremltools pillow
  python ml/convert_huggingface_mobilenetv2.py --check      # tests the model on the 10 bundled tomato sample leaves first
Output: ml/AgriNovaLeaf.mlpackage  → copy to AgriNova/Resources/Models/ and run ./scripts/bootstrap.sh

The app only diagnoses tomato; for the other 28 classes it shows "This doesn't look like a tomato leaf".
NOTE: I could not run this script myself (no Mac / HF access in my environment) – treat it as untested and read the printed labels.
"""
import argparse, glob, os, sys
import torch, torch.nn as nn
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForImageClassification
import coremltools as ct

MODEL_ID = "linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification"
SAMPLES = os.path.join(os.path.dirname(__file__), "..", "AgriNova", "Resources", "SampleLeaves")
OUT = os.path.join(os.path.dirname(__file__), "AgriNovaLeaf.mlpackage")
# sample-file key -> substring expected in the predicted label (lower-case, spaces→underscores)
EXPECT = {"bacterial_spot": "tomato___bacterial_spot", "early_blight": "tomato___early_blight", "late_blight": "tomato___late_blight",
          "leaf_mold": "tomato___leaf_mold", "septoria": "tomato___septoria", "spider_mites": "tomato___spider_mites",
          "target_spot": "tomato___target_spot", "yellow_leaf_curl": "tomato___tomato_yellow_leaf_curl", "mosaic": "tomato___tomato_mosaic",
          "healthy": "tomato___healthy"}

ap = argparse.ArgumentParser(); ap.add_argument("--check", action="store_true"); args = ap.parse_args()

model = AutoModelForImageClassification.from_pretrained(MODEL_ID).eval()
proc = AutoImageProcessor.from_pretrained(MODEL_ID)
labels = [model.config.id2label[i] for i in range(model.config.num_labels)]
print(f"{len(labels)} classes. Tomato classes found:", [l for l in labels if "tomato" in l.lower()])
size = proc.crop_size["height"] if getattr(proc, "crop_size", None) else 224
mean, std = proc.image_mean, proc.image_std
print("input size", size, "mean", mean, "std", std)

if args.check:
    ok = total = 0
    for key, want in EXPECT.items():
        for f in sorted(glob.glob(os.path.join(SAMPLES, f"sample_{key}_*.jpg"))):
            inputs = proc(images=Image.open(f).convert("RGB"), return_tensors="pt")
            with torch.no_grad():
                pred = model(**inputs).logits.argmax(1).item()
            name = labels[pred].lower().replace(" ", "_")
            hit = want in name; ok += int(hit); total += 1
            print(f"{os.path.basename(f):34s} -> {labels[pred]:55s} {'OK' if hit else 'X'}")
    print(f"\nsample accuracy {ok}/{total}")
    if total and ok / total < 0.7: sys.exit("Low accuracy – label names differ from the expected PlantVillage names. Check the printed labels.")

class Wrap(nn.Module):
    """Normalisation + softmax inside the model so Vision only supplies a 0-1 RGB image."""
    def __init__(self, m):
        super().__init__()
        self.m = m
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))
    def forward(self, x):
        return torch.softmax(self.m(pixel_values=(x - self.mean) / self.std, return_dict=False)[0], dim=1)

traced = torch.jit.trace(Wrap(model).eval(), torch.rand(1, 3, size, size), strict=False)
mlmodel = ct.convert(traced,
    inputs=[ct.ImageType(name="image", shape=(1, 3, size, size), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
    classifier_config=ct.ClassifierConfig(labels), minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram")
mlmodel.short_description = "AgriNova leaf disease classifier – MobileNetV2 fine-tuned on PlantVillage (converted from Hugging Face)"
mlmodel.author = "linkanjarad (model) / converted for AgriNova"
mlmodel.save(OUT); print("saved", OUT)
