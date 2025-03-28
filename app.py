from flask import Flask, request, jsonify
from flask_cors import CORS
import ee
import numpy as np
import tensorflow as tf
import xgboost as xgb
import requests
from PIL import Image
from io import BytesIO

app = Flask(__name__)
CORS(app)

# 🌍 Initialize Google Earth Engine with Project ID
PROJECT_ID = "ee-rrojitha71"  # Change this to your GEE project ID
ee.Initialize(project=PROJECT_ID)

# 🧠 Load AI Models
cnn_model = tf.keras.models.load_model("wildfire_model_limited.h5", compile=False)
xgb_model = xgb.XGBClassifier()
xgb_model.load_model("fire_model1.json")

@app.route("/predict", methods=["POST"])
def predict():
    try:
        # Get the latitude and longitude from the request
        data = request.json
        lat, lon = data.get("lat"), data.get("lon")

        if lat is None or lon is None:
            return jsonify({"error": "Latitude and longitude are required"}), 400

        # 🗺️ Generate Bounding Box (Adjust size if needed)
        bbox = ee.Geometry.BBox(lon - 0.3, lat - 0.3, lon + 0.3, lat + 0.3)

        # 🛰️ Fetch Sentinel-2 Image
        sentinel_collection = (
            ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
            .filterBounds(bbox)
            .filterDate(ee.Date("2024-03-01"), ee.Date("2024-03-24"))  # Adjust date range as needed
            .sort("system:time_start", False)
        )
        latest_image = sentinel_collection.first().select(["B4", "B3", "B2"])

        if latest_image is None:
            return jsonify({"error": "No Sentinel-2 image found for the given location."}), 404

        # 📸 Convert Image to URL
        image_url = latest_image.visualize(min=0, max=3000, bands=["B4", "B3", "B2"]).getThumbURL({
            "region": bbox.getInfo(), "scale": 50, "format": "png"
        })

        # 🖼️ Process Image for CNN Model
        response = requests.get(image_url)
        image = Image.open(BytesIO(response.content)).convert("RGB")
        image = image.resize((150, 150))  # Resize image to fit the model input size
        image_array = np.array(image) / 255.0  # Normalize image
        image_array = np.expand_dims(image_array, axis=0)

        # 🔥 CNN Prediction
        cnn_prediction = cnn_model.predict(image_array)[0][0]

        # 🌦️ Fetch Weather Data
        API_KEY = "882c7ba9bc4358298d4e08b801b60416"  # Replace with your actual OpenWeatherMap API key
        weather_url = f"http://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={API_KEY}&units=metric"
        weather_data = requests.get(weather_url).json()

        if "main" not in weather_data or "wind" not in weather_data:
            return jsonify({"error": "Failed to fetch weather data."}), 500

        temperature = weather_data['main']['temp']
        humidity = weather_data['main']['humidity']
        wind_speed = weather_data['wind']['speed']
        rainfall = weather_data.get('rain', {}).get('1h', 0)

        # 📊 XGBoost Prediction
        xgb_input = np.array([[temperature, humidity, wind_speed, rainfall]])
        xgb_prediction = xgb_model.predict_proba(xgb_input)[0][1]

        # 🔥 Final Risk Calculation
        final_prob = (0.6 * cnn_prediction) + (0.4 * xgb_prediction)

        # Return prediction data
        return jsonify({
            "location": [lat, lon],
            "temperature": temperature,
            "humidity": humidity,
            "wind_speed": wind_speed,
            "rainfall": rainfall,
            "cnn_prediction": float(cnn_prediction),
            "xgb_prediction": float(xgb_prediction),
            "final_prob": float(final_prob),
            "risk_level": "High" if final_prob > 0.5 else "Low"
        })

    except Exception as e:
        # If there is an error, return it
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True)
