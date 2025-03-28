import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String? geometryString;
  String? predictionResult; // Store API response

  /// 🔍 Fetch location suggestions from API
  Future<List<Map<String, dynamic>>> _searchLocation(String query) async {
    final result = await ApiService.fetchLocation(query);
    return result != null ? [result] : [];
  }

  /// 📡 Send extracted lat/lon to Flask API
  Future<void> _sendToApi(String geometry) async {
    // Extract lat and lon from geometry string
    final regex = RegExp(r'BBox\((.*?), (.*?), (.*?), (.*?)\)');
    final match = regex.firstMatch(geometry);

    if (match != null) {
      double lon1 = double.parse(match.group(1)!);
      double lat1 = double.parse(match.group(2)!);
      double lon2 = double.parse(match.group(3)!);
      double lat2 = double.parse(match.group(4)!);

      // Calculate center coordinates
      double lat = (lat1 + lat2) / 2;
      double lon = (lon1 + lon2) / 2;

      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/predict'), // Flask API URL
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"lat": lat, "lon": lon}), // Send as JSON
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          predictionResult = "🔥 Fire Risk: ${data['risk_level']}"; // Show risk level
        });
      } else {
        setState(() {
          predictionResult = "Error: ${response.statusCode}";
        });
      }
    } else {
      setState(() {
        predictionResult = "Invalid geometry format";
      });
    }
  }

  /// 📌 Convert location to Earth Engine geometry and send to API
  Future<void> _setGeometry(Map<String, dynamic> location) async {
    double lat = location["lat"];
    double lon = location["lon"];
    double latDelta = 0.3;
    double lonDelta = 0.3;

    // Now, send the 4 values directly
    double minLat = lat - latDelta;
    double maxLat = lat + latDelta;
    double minLon = lon - lonDelta;
    double maxLon = lon + lonDelta;

    // Directly send the bounding box values
    final response = await http.post(
      Uri.parse('http://10.0.2.2:5000/predict'), // Flask API URL
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "min_lon": minLon,  // min longitude
        "min_lat": minLat,  // min latitude
        "max_lon": maxLon,  // max longitude
        "max_lat": maxLat,  // max latitude
      }), // Send the bounding box directly
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        predictionResult = "🔥 Fire Risk: ${data['risk_level']}"; // Show risk level
      });
    } else {
      setState(() {
        predictionResult = "Error: ${response.statusCode}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Location Search")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TypeAheadField<Map<String, dynamic>>(
              textFieldConfiguration: TextFieldConfiguration(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: "Search Location",
                  border: OutlineInputBorder(),
                ),
              ),
              suggestionsCallback: _searchLocation,
              itemBuilder: (context, suggestion) {
                return ListTile(title: Text(suggestion["name"]));
              },
              onSuggestionSelected: (suggestion) {
                _searchController.text = suggestion["name"];
                _setGeometry(suggestion);
              },
            ),
            const SizedBox(height: 20),
            if (geometryString != null)
              Text(
                "Generated Geometry:\n$geometryString",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 20),
            if (predictionResult != null)
              Text(
                predictionResult!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
