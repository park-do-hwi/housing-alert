import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 사용자가 고르는 파일 저장·열기. 화면 테스트에서 가짜로 바꿀 수 있게 분리했다.
abstract class FileIo {
  /// 파일로 저장. 저장했으면 true, 사용자가 취소했으면 false.
  Future<bool> save(String fileName, Uint8List bytes);

  /// 파일 하나를 골라 내용을 읽는다. 취소하면 null.
  Future<Uint8List?> pick();
}

class PickerFileIo implements FileIo {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: '내 정보 파일 저장',
    );
    return uri != null;
  }

  @override
  Future<Uint8List?> pick() async {
    final f = await FilePicker.pickFile(dialogTitle: '내 정보 파일 선택');
    return f?.readAsBytes();
  }
}
