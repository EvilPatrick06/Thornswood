// The Flutter prototype for the launcher stack study (#3209): Flutter's own
// renderer in a Windows window. README.md has the contract every prototype
// keeps. The platform folders come from `flutter create .`, run by the build
// script, so only this file and pubspec.yaml are ours.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

final String here = File(Platform.resolvedExecutable).parent.path;
final String? readyFile = Platform.environment['PROTO_READY'];

void music() {
  if (!Platform.isWindows) return;
  final winmm = DynamicLibrary.open('winmm.dll');
  final playSound = winmm.lookupFunction<Int32 Function(Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Utf16>, int, int)>('PlaySoundW');
  final path = '$here${Platform.pathSeparator}loop.wav'.toNativeUtf16();
  playSound(path, 0, 0x1 | 0x8 | 0x20000);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.Image? art;
  final file = File('$here${Platform.pathSeparator}art.png');
  if (file.existsSync()) {
    final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
    art = (await codec.getNextFrame()).image;
  }
  runApp(Proto(art: art));
}

class Proto extends StatefulWidget {
  const Proto({super.key, required this.art});
  final ui.Image? art;
  @override
  State<Proto> createState() => _ProtoState();
}

class _ProtoState extends State<Proto> {
  String state = 'Ready to launch';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (readyFile != null && readyFile!.isNotEmpty) File(readyFile!).writeAsStringSync('ready');
      Timer(const Duration(seconds: 4), play);
    });
  }

  Future<void> play() async {
    music();
    final p = Platform.isWindows ? await Process.start('cmd.exe', ['/c', 'exit', '0']) : await Process.start('true', []);
    setState(() => state = 'Started ${p.pid}');
    if (readyFile != null && readyFile!.isNotEmpty) File('${readyFile!}.active').writeAsStringSync('active');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thornswood flutter',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF14110E),
        body: Stack(fit: StackFit.expand, children: [
          if (widget.art != null) RawImage(image: widget.art, fit: BoxFit.cover),
          Positioned(
            left: 48,
            bottom: 48,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('THORNSWOOD', style: TextStyle(fontSize: 40, color: Color(0xFFEADFC8))),
              const SizedBox(height: 12),
              SizedBox(width: 220, height: 56, child: FilledButton(onPressed: play, child: const Text('Play', style: TextStyle(fontSize: 20)))),
              const SizedBox(height: 12),
              Text(state, style: const TextStyle(color: Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }
}
