import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:iconsax/iconsax.dart';

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Location _locationController = Location();

  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;
  StreamSubscription<LocationData>? _locationSubscription;

  final double _geofenceRadius = 1000; // 5000 meters

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeMapData() async {
    // Set default car icon if custom asset fails to load
    _carIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

    try {
      await _createCarMarkerIcon();
    } catch (e) {
      print("Failed to load car icon: $e");
    }

    await getLocationUpdates();
    await fetchVehicles();
  }

  Future<void> _createCarMarkerIcon() async {
    try {
      if (!mounted) return;
      final Uint8List markerIcon =
          await getBytesFromAsset('assets/images/car_icon.png', 80);
      _carIcon = BitmapDescriptor.fromBytes(markerIcon);
    } catch (e) {
      print("Error creating car marker icon: $e");
    }
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await DefaultAssetBundle.of(context).load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Find Nearest Vehicles"),
        backgroundColor: Colors.white54,
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition!,
                    zoom: 14,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _markers,
                  circles: _circles,
                  mapType: MapType.normal,
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: FloatingActionButton(
                    backgroundColor: const Color.fromARGB(247, 63, 138, 236),
                    child: const Icon(Icons.refresh),
                    onPressed: fetchVehicles,
                    tooltip: 'Refresh Vehicles',
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> getLocationUpdates() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    try {
      _serviceEnabled = await _locationController.serviceEnabled();
      if (!_serviceEnabled) {
        _serviceEnabled = await _locationController.requestService();
        if (!_serviceEnabled) {
          throw Exception("Location services are disabled");
        }
      }

      _permissionGranted = await _locationController.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _permissionGranted = await _locationController.requestPermission();
        if (_permissionGranted != PermissionStatus.granted) {
          throw Exception("Location permission not granted");
        }
      }

      // Get initial location
      final initialLocation = await _locationController.getLocation();
      if (initialLocation.latitude != null &&
          initialLocation.longitude != null) {
        setState(() {
          _currentPosition =
              LatLng(initialLocation.latitude!, initialLocation.longitude!);
          _updateGeofence();
        });
      }

      // Start location updates
      _locationSubscription = _locationController.onLocationChanged
          .listen((LocationData currentLocation) {
        if (mounted &&
            currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          setState(() {
            _currentPosition =
                LatLng(currentLocation.latitude!, currentLocation.longitude!);
            _updateGeofence();
          });
        }
      });
    } catch (e) {
      print("Error getting location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Future<void> fetchVehicles() async {
    if (!mounted) return;
    try {
      // Predefined list of vehicles with static locations
      final List<Map<String, dynamic>> vehiclesData = [
        {
          'id': '1',
          'location': LatLng(37.7749, -122.4194), // Example: San Francisco
          'name': 'Vehicle 1',
          'status': 'Available',
          'distance': '500m',
        },
        {
          'id': '2',
          'location': LatLng(34.0522, -118.2437), // Example: Los Angeles
          'name': 'Vehicle 2',
          'status': 'Available',
          'distance': '1km',
        },
        {
          'id': '3',
          'location': LatLng(40.7128, -74.0060), // Example: New York
          'name': 'Vehicle 3',
          'status': 'Available',
          'distance': '2km',
        },
      ];

      // Update markers on the map based on the predefined list of vehicle locations
      setState(() {
        _markers = vehiclesData.map((data) {
          return Marker(
            markerId: MarkerId(data['id']),
            position: data['location'],
            icon: _carIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () =>
                _showVehicleDetails(data, data['location'], data['id']),
          );
        }).toSet();
      });
    } catch (e) {
      print("Error fetching vehicles: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load vehicles: $e")),
        );
      }
    }
  }

  void _updateGeofence() {
    if (_currentPosition != null) {
      setState(() {
        _circles = {
          Circle(
            circleId: const CircleId("geofence"),
            center: _currentPosition!,
            radius: _geofenceRadius,
            fillColor: Colors.blue.withOpacity(0.1),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          )
        };
      });
    }
  }

  void _showVehicleDetails(Map<String, dynamic> vehicleData,
      LatLng vehiclePosition, String documentId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(vehicleData['name']),
              IconButton(
                icon: const Icon(Iconsax.close_circle),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SizedBox(
            height: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Iconsax.car),
                Text("Status: ${vehicleData['status']}"),
                Text("Distance: ${vehicleData['distance']}"),
                Text(
                    "Location: ${vehiclePosition.latitude}, ${vehiclePosition.longitude}"),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Book Now"),
              onPressed: () {
                // Add booking functionality here
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
