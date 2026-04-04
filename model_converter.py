import os
import argparse

# 1. Configuration
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KERAS_MODEL_PATH = os.path.join(_SCRIPT_DIR, "server/final_model.keras")  # classifier head
FULL_MODEL_PATH = os.path.join(_SCRIPT_DIR, "server/final_model_end_to_end.keras")
TFLITE_OUTPUT_PATH = os.path.join(_SCRIPT_DIR, "mobile/assets/tobacco_model.tflite")
IMAGE_SIZE = (300, 300)


def load_tensorflow():
    try:
        import tensorflow as tf  # local import for clearer startup errors
        return tf
    except Exception as exc:
        print("Error: TensorFlow failed to import.")
        print(f"Details: {exc}")
        print("\nLikely cause on macOS: incompatible/broken tensorflow-metal plugin.")
        print("Quick fix:")
        print("  1) .venv/bin/python -m pip uninstall -y tensorflow-metal")
        print("  2) .venv/bin/python model_converter.py")
        print("\nIf still broken, rebuild venv with Python 3.10/3.11 and reinstall TensorFlow.")
        return None

def build_end_to_end_model(tf, classifier_model_path, save_keras_path=None):
    """Build image->EfficientNetB3->classifier graph for true offline parity."""
    if not os.path.exists(classifier_model_path):
        raise FileNotFoundError(f"{classifier_model_path} not found")

    print("Loading classifier head model...")
    classifier = tf.keras.models.load_model(classifier_model_path)

    print("Building EfficientNetB3 feature extractor...")
    feature_extractor = tf.keras.applications.EfficientNetB3(
        weights="imagenet",
        include_top=False,
        pooling="avg",
        input_shape=(IMAGE_SIZE[0], IMAGE_SIZE[1], 3),
    )
    feature_extractor.trainable = False

    # Must match server/server.py: keras EfficientNetB3 + preprocess_input (ImageNet mean/std).
    # Rescaling to [-1,1] is NOT the same and yields ~flat wrong logits (~48% top class).
    model_input = tf.keras.Input(shape=(IMAGE_SIZE[0], IMAGE_SIZE[1], 3), name="image")
    x = tf.keras.layers.Lambda(
        lambda img: tf.keras.applications.efficientnet.preprocess_input(img),
        name="efficientnet_preprocess",
        output_shape=(IMAGE_SIZE[0], IMAGE_SIZE[1], 3),
    )(model_input)
    features = feature_extractor(x, training=False)
    outputs = classifier(features, training=False)
    end_to_end_model = tf.keras.Model(inputs=model_input, outputs=outputs, name="tobacco_end_to_end")

    if save_keras_path:
        end_to_end_model.save(save_keras_path)
        print(f"Saved end-to-end Keras model to: {save_keras_path}")

    return end_to_end_model


def convert_model(use_end_to_end=True):
    tf = load_tensorflow()
    if tf is None:
        return

    if not os.path.exists(KERAS_MODEL_PATH):
        print(f"Error: {KERAS_MODEL_PATH} not found!")
        return

    if use_end_to_end:
        model = build_end_to_end_model(tf, KERAS_MODEL_PATH, save_keras_path=FULL_MODEL_PATH)
    else:
        print("Loading classifier-only Keras model...")
        model = tf.keras.models.load_model(KERAS_MODEL_PATH)

    # 2. Initialize the Converter
    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    # 3. Apply Optimizations (Quantization)
    # This reduces size (e.g., 50MB -> 12MB) and speeds up mobile inference
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # Ensure the model supports mobile-friendly operations
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS, # Standard TFLite ops
        tf.lite.OpsSet.SELECT_TF_OPS   # Flex ops if your model uses complex layers
    ]

    print("Converting to TFLite... this may take a minute.")
    tflite_model = converter.convert()

    # 4. Save the Result
    with open(TFLITE_OUTPUT_PATH, 'wb') as f:
        f.write(tflite_model)

    print(f"Successfully converted! Saved to: {TFLITE_OUTPUT_PATH}")
    print(f"Classifier model size: {os.path.getsize(KERAS_MODEL_PATH) / 1024 / 1024:.2f} MB")
    if os.path.exists(FULL_MODEL_PATH):
        print(f"End-to-end Keras size: {os.path.getsize(FULL_MODEL_PATH) / 1024 / 1024:.2f} MB")
    print(f"TFLite size: {os.path.getsize(TFLITE_OUTPUT_PATH) / 1024 / 1024:.2f} MB")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert tobacco model to TFLite.")
    parser.add_argument(
        "--classifier-only",
        action="store_true",
        help="Convert only final_model.keras (legacy mode, expects feature vectors).",
    )
    args = parser.parse_args()

    convert_model(use_end_to_end=not args.classifier_only)