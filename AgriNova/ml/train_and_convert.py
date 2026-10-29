#!/usr/bin/env python3
"""
Train a tomato-leaf disease classifier (MobileNetV2 transfer learning) and convert it to Core ML.

  pip install torch torchvision coremltools pillow
  ./scripts/prepare_dataset.sh 600        # builds ml/dataset/<Class>/*.JPG
  python ml/train_and_convert.py           # ~15-30 min on a Colab GPU, slower on CPU

Output: ml/AgriNovaLeaf.mlpackage  -> copy into AgriNova/Resources/Models/
The class labels are the dataset folder names, e.g. "Tomato___Early_blight", exactly what DiseaseCatalog expects.
"""
import os, sys, random
import torch, torch.nn as nn
from torch.utils.data import DataLoader, random_split
from torchvision import datasets, transforms, models
import coremltools as ct

DATA = os.path.join(os.path.dirname(__file__), "dataset")
OUT = os.path.join(os.path.dirname(__file__), "AgriNovaLeaf.mlpackage")
EPOCHS, BATCH, SIZE = 6, 32, 224
device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
print("device:", device)

train_tf = transforms.Compose([
    transforms.RandomResizedCrop(SIZE, scale=(0.6, 1.0)), transforms.RandomHorizontalFlip(), transforms.RandomVerticalFlip(),
    transforms.ColorJitter(0.3, 0.3, 0.3, 0.05), transforms.RandomRotation(25), transforms.ToTensor()])
val_tf = transforms.Compose([transforms.Resize((SIZE, SIZE)), transforms.ToTensor()])

full = datasets.ImageFolder(DATA)
classes = full.classes
print("classes:", classes)
n_val = int(0.2 * len(full)); n_train = len(full) - n_val
g = torch.Generator().manual_seed(42)
tr_idx, va_idx = random_split(range(len(full)), [n_train, n_val], generator=g)

class Subset(torch.utils.data.Dataset):
    def __init__(self, idx, tf): self.idx, self.tf = list(idx), tf
    def __len__(self): return len(self.idx)
    def __getitem__(self, i):
        img, y = full[self.idx[i]]
        return self.tf(img), y
train_dl = DataLoader(Subset(tr_idx, train_tf), batch_size=BATCH, shuffle=True, num_workers=2)
val_dl = DataLoader(Subset(va_idx, val_tf), batch_size=BATCH, num_workers=2)

# Normalisation lives INSIDE the model so Core ML / Vision only needs a 0-1 RGB image.
class Net(nn.Module):
    def __init__(self, n):
        super().__init__()
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))
        self.backbone = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)
        self.backbone.classifier[1] = nn.Linear(self.backbone.last_channel, n)
    def forward(self, x):
        return torch.softmax(self.backbone((x - self.mean) / self.std), dim=1)

model = Net(len(classes)).to(device)
opt = torch.optim.AdamW(model.parameters(), lr=3e-4, weight_decay=1e-4)
sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS)
loss_fn = nn.NLLLoss()

for epoch in range(EPOCHS):
    model.train()
    for x, y in train_dl:
        x, y = x.to(device), y.to(device)
        opt.zero_grad()
        loss = loss_fn(torch.log(model(x) + 1e-8), y)
        loss.backward(); opt.step()
    sched.step()
    model.eval(); correct = total = 0
    with torch.no_grad():
        for x, y in val_dl:
            pred = model(x.to(device)).argmax(1).cpu()
            correct += (pred == y).sum().item(); total += len(y)
    print(f"epoch {epoch+1}/{EPOCHS}  val accuracy {correct/total:.3f}")

model.eval().cpu()
traced = torch.jit.trace(model, torch.rand(1, 3, SIZE, SIZE))
mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(name="image", shape=(1, 3, SIZE, SIZE), scale=1/255.0, color_layout=ct.colorlayout.RGB)],
    classifier_config=ct.ClassifierConfig(classes),
    minimum_deployment_target=ct.target.iOS16,
    convert_to="mlprogram")
mlmodel.short_description = "AgriNova tomato leaf disease classifier (PlantVillage, MobileNetV2)"
mlmodel.author = "AgriNova"
mlmodel.save(OUT)
print("saved", OUT)
