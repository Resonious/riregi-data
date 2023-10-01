require 'active_support/core_ext/string'
require 'tempfile'

def type_to_dart_native(return_type)
  return_type = return_type.tr '?', ''

  return 'Pointer<Utf8>' if return_type == '[*c]const u8'
  return 'Pointer<Utf8>' if return_type == '[*:0]const u8'
  return 'Pointer<Void>' if return_type == '*anyopaque'
  return 'Void' if return_type == 'void'
  return 'Int' if return_type == 'c_int'

  /^(?<sign>[ui])(?<bits>\d+)$/ =~ return_type

  return "Int#{bits}" if sign == 'i'
  return "Uint#{bits}" if sign == 'u'

  raise "Unexpected type #{return_type}"
end

def type_to_dart(return_type)
  return_type = return_type.tr '?', ''

  return 'Pointer<Utf8>' if return_type == '[*c]const u8'
  return 'Pointer<Utf8>' if return_type == '[*:0]const u8'
  return 'Pointer<Void>' if return_type == '*anyopaque'
  return 'void' if return_type == 'void'
  return 'int' if return_type == 'c_int'

  /^(?<sign>[ui])(?<bits>\d+)$/ =~ return_type

  return 'int' if sign && bits

  raise "Unexpected type #{return_type}"
end

Function = Struct.new(:name, :args, :return_type)

@text = File.read('src/main.zig')

TypeRegex = '([\w\*\?]+)|(\[\*c\]const u8)|(\[\*:0\]const u8)'

@exports = @text.scan(/export fn (?<name>rr_\w+)\((?<args>.*?)\) (?<return_type>#{TypeRegex}) \{/m)

@functions = @exports.map do |export|
  Function.new(
    export[0],
    export[1].scan(/\w+: (?<type>#{TypeRegex})/).flatten,
    export[2],
  )
end

@result = <<~DART
import 'dart:developer';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

DART

@functions.each do |fn|
  @result += 'typedef '
  @result += fn.name.sub('rr', 'RR').camelize
  @result += 'Native = '
  @result += type_to_dart_native(fn.return_type)
  @result += ' Function('
  @result += fn.args.map { |a| type_to_dart_native(a)}.join(', ')
  @result += ");\n"

  @result += 'typedef '
  @result += fn.name.sub('rr', 'RR').camelize
  @result += ' = '
  @result += type_to_dart(fn.return_type)
  @result += ' Function('
  @result += fn.args.map { |a| type_to_dart(a)}.join(', ')
  @result += ");\n"
end

@result += <<DART

class ActiveAppState {
  final DynamicLibrary lib;
  final String dataPath;

DART

@functions.each do |fn|
  @result += '  late final '
  @result += fn.name.sub('rr', 'RR').camelize
  @result += ' '
  @result += fn.name.camelize(:lower)
  @result += ";\n"
end

@result += <<DART

  late final Pointer<Void> ctx;

  ActiveAppState({required this.lib, required this.dataPath}) {
DART

@functions.each do |fn|
  #  rrStart = lib.lookupFunction<RRStartNative, RRStart>("rr_start");
  @result += '    '
  @result += fn.name.camelize(:lower)
  @result += ' = lib.lookupFunction<'
  @result += fn.name.sub('rr', 'RR').camelize
  @result += 'Native, '
  @result += fn.name.sub('rr', 'RR').camelize
  @result += '>('
  @result += fn.name.inspect
  @result += ");\n"
end

@result += <<DART

    final path = dataPath.toNativeUtf8();
    ctx = rrStart(path, path.length);
    if (ctx.address == 0) {
      log('we have a problem');
    }
  }
}
DART

Tempfile.create('data.dart') do |file|
  file.write @result
  file.flush

  `dart format #{file.path}`
  file.rewind
  puts file.read
end

