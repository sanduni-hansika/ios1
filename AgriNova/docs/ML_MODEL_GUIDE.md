# Core ML model – from zero to hero

**Why you must do this step:** the brief requires on-device ML, and I (the AI that wrote this app) could not train a model in my sandbox
(no Mac, no GPU, blocked PyTorch download host). I also did **not** find a pre-trained tomato-disease `.mlmodel` whose download link I could verify,
so I won't give you a link I can't vouch for. The app expects a classifier called **`AgriNovaLeaf`** whose class labels are:

```
Tomato___Bacterial_spot   Tomato___Early_blight   Tomato___Late_blight   Tomato___Leaf_Mold   Tomato___Septoria_leaf_spot
Tomato___Spider_mites Two-spotted_spider_mite   Tomato___Target_Spot   Tomato___Tomato_Yellow_Leaf_Curl_Virus
Tomato___Tomato_mosaic_virus   Tomato___healthy
```
Dataset (verified, public): https://github.com/spMohanty/PlantVillage-Dataset  (folder `raw/color`).

## Path 0 – use a pre-trained MobileNetV2 (RECOMMENDED – this is what the coursework intends: convert, don't train)
**Did I include a trained model in the zip? No** – my environment has no Mac, no GPU and no access to download model weights, so I could not fetch or convert one. But I found a real, public one that matches your proposal text (MobileNetV2):
**`linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification` on Hugging Face** – https://huggingface.co/linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification
(MobileNetV2 fine-tuned on PlantVillage, 38 crop classes including all 10 tomato classes, reported accuracy 95.4 %. Its licence field says "other" – cite the model and its author in your report.)
Small steps (Mac, Terminal):
1. `python3 -m venv ml/venv && source ml/venv/bin/activate`
2. `pip install torch torchvision transformers coremltools pillow`
3. `python ml/convert_huggingface_mobilenetv2.py --check`
   – downloads the model, prints its class names, runs the 10 tomato sample leaves bundled in the app through it and prints `sample accuracy N/…`. If it is below 7/10 it stops (label names differ) – read the printed labels and tell me.
4. It writes `ml/AgriNovaLeaf.mlpackage`. Copy it into `AgriNova/Resources/Models/`.
5. `./scripts/bootstrap.sh` then ⌘R. Settings ▸ Seed Data console ▸ *Classify all 10 samples* should show mostly correct predictions.
6. Because the model knows 38 classes, the app shows "This doesn't look like a tomato leaf" for potato/apple/etc. instead of a wrong tomato diagnosis (tested logic: `DiseaseCatalog.find` + `ScanViewModel`).
I have NOT run this script (untested). If it fails, use Path A (Create ML) below.

### Path 0b – an AlexNet/VGG13 tomato-only model
See `ml/convert_pretrained_pytorch.py` (links in the README of github.com/shywel/DeepLearning_PlantDiseases). Architecture is AlexNet/VGG13, not MobileNetV2, so say that in your report.

## Path A – easiest (no code): Create ML on your Mac (~20 min)
1. `./scripts/prepare_dataset.sh 600` → creates `ml/dataset/<ClassName>/` folders (600 images/class). Folder names = labels, don't rename.
2. Xcode ▸ Open Developer Tool ▸ **Create ML** ▸ New Document ▸ **Image Classifier**.
3. Training Data → choose `ml/dataset`. Set *Validation* = Auto (or split 80/20). Augmentations: tick *Flip, Rotate, Crop, Exposure, Blur* (helps real farm photos).
4. Press **Train**. Look at Validation accuracy (aim ≥ 90 %; PlantVillage is easy, real-field accuracy will be lower — mention this limitation in your report).
5. *Output* tab → **Get** → save as **`AgriNovaLeaf.mlmodel`**.
6. Drag it to `AgriNova/Resources/Models/`, run `./scripts/bootstrap.sh`, build. Done – Xcode compiles it into `AgriNovaLeaf.mlmodelc`, which `LeafClassifier` loads.

## Path B – Python transfer learning (better accuracy, Colab-friendly)
```bash
pip install torch torchvision coremltools pillow
./scripts/prepare_dataset.sh 600
python ml/train_and_convert.py        # prints validation accuracy per epoch, writes ml/AgriNovaLeaf.mlpackage
```
Copy `ml/AgriNovaLeaf.mlpackage` into `AgriNova/Resources/Models/`. (On Colab: upload the repo, enable a GPU runtime, run the same commands, download the `.mlpackage` zip.)

## Verify it works
Run the app → Settings ▸ Seed Data console ▸ *Classify all 10 samples*. Each row logs the real prediction. If a class is wrong, train longer / use more images.
The app **never fakes results**: with no model it shows an "AI model not installed" card.

## Make it better (talking points for your viva)
- Add real field photos from Sri Lankan farms (PlantVillage images are lab-style on plain backgrounds, so accuracy drops in the field).
- Use class-balanced sampling, more epochs, test-time augmentation.
- Quantise (`compute_precision=ct.precision.FLOAT16` is default) to shrink the model.
- Evaluate with a confusion matrix; justify the 70 % confidence gate with the confidence histogram from the Insights screen.
