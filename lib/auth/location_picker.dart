import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app.dart';

const LatLng kCairo = LatLng(30.0444, 31.2357);

TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.sol.store',
    );

Future<LatLng?> currentLocation(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) toast(context, 'افتح الـ GPS (الموقع) من الموبايل', error: true);
      return null;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (context.mounted) toast(context, 'لازم توافق على إذن الموقع', error: true);
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    return LatLng(pos.latitude, pos.longitude);
  } catch (e) {
    if (context.mounted) toast(context, 'مقدرناش نحدد موقعك: $e', error: true);
    return null;
  }
}

Future<void> openDirections(double lat, double lng) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// شاشة تحديد موقع المحل على الخريطة
class LocationPicker extends StatefulWidget {
  final LatLng? initial;
  const LocationPicker({super.key, this.initial});
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final map = MapController();
  LatLng? point;
  bool locating = false;

  @override
  void initState() {
    super.initState();
    point = widget.initial;
    if (point == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => myLocation());
    }
  }

  Future<void> myLocation() async {
    setState(() => locating = true);
    final p = await currentLocation(context);
    if (!mounted) return;
    setState(() {
      locating = false;
      if (p != null) point = p;
    });
    if (p != null) map.move(p, 17);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حدد مكان المحل')),
      body: Stack(children: [
        FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: point ?? kCairo,
            initialZoom: point == null ? 11 : 17,
            onTap: (_, ll) => setState(() => point = ll),
          ),
          children: [
            osmTiles(),
            if (point != null)
              MarkerLayer(markers: [
                Marker(
                  point: point!,
                  width: 50,
                  height: 50,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_pin, color: kDanger, size: 50),
                ),
              ]),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                point == null
                    ? 'دوس على مكان المحل في الخريطة أو استخدم زرار "موقعي"'
                    : 'تمام ✔ لو المكان مش مظبوط دوس على المكان الصح',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 90,
          left: 16,
          child: FloatingActionButton(
            heroTag: 'myloc',
            onPressed: locating ? null : myLocation,
            child: locating
                ? const CircularProgressIndicator()
                : const Icon(Icons.my_location),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: point == null ? null : () => Navigator.pop(context, point),
            icon: const Icon(Icons.check),
            label: const Text('تأكيد الموقع'),
          ),
        ),
      ),
    );
  }
}

/// خريطة صغيرة لعرض موقع محل + زرار الاتجاهات
class ShopMap extends StatelessWidget {
  final double lat, lng;
  final double height;
  const ShopMap({super.key, required this.lat, required this.lng, this.height = 180});
  @override
  Widget build(BuildContext context) {
    final p = LatLng(lat, lng);
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: p,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
            ),
            children: [
              osmTiles(),
              MarkerLayer(markers: [
                Marker(
                  point: p,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_pin, color: kDanger, size: 40),
                ),
              ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => openDirections(lat, lng),
          icon: const Icon(Icons.directions),
          label: const Text('وديني للمحل (جوجل ماب)'),
        ),
      ),
    ]);
  }
}
