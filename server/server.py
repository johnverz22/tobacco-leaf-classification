from flask import Flask, request, jsonify
from flask_cors import CORS
import tensorflow as tf
import numpy as np
from PIL import Image
from tensorflow.keras.preprocessing import image as keras_image
from tensorflow.keras.applications.efficientnet import preprocess_input
from tensorflow.keras.applications import EfficientNetB3

# Initialize Flask app
app = Flask(__name__)
CORS(app) #Enable CORS for all routes

# Load your trained classifier model
try:
    model = tf.keras.models.load_model("final_model.keras")
except Exception as e:
    raise RuntimeError(f"Failed to load model: {e}")

# Load EfficientNetB3 for feature extraction
feature_extractor = EfficientNetB3(
    weights='imagenet',
    include_top=False,
    pooling='avg',
    input_shape=(300, 300, 3)
)

# Class labels
class_labels = ['AX', 'BX', 'CX', 'DX', 'K3']


def preprocess_and_extract(img_pil):
    """Preprocess image and extract features using EfficientNetB3."""
    img = img_pil.resize((300, 300))
    img_array = keras_image.img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0)
    img_array = preprocess_input(img_array)
    features = feature_extractor.predict(img_array, verbose=0)
    return features


@app.route("/predict", methods=["POST"])
def predict():
    """Predict the class from uploaded image."""
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400

    try:
        img_file = request.files['image']
        img = Image.open(img_file.stream).convert("RGB")

        features = preprocess_and_extract(img)
        prediction = model.predict(features, verbose=0)

        predicted_class = class_labels[np.argmax(prediction)]
        confidence = float(np.max(prediction)) * 100

        return jsonify({
            'prediction': predicted_class,
            'confidence': f"{confidence:.2f}%"
        })
    except Exception as e:
        return jsonify({'error': f'Prediction failed: {str(e)}'}), 500


if __name__ == "__main__":
    # Run Flask server on 0.0.0.0 to work with NGROK
    app.run(host='0.0.0.0', port=8090, debug=True)
