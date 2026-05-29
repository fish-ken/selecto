import '../output_decoder.dart';
import '../preprocessing.dart';
import 'model_config.dart';

/// NIMA MobileNet aesthetic head — 224×224 NCHW, MobileNet preprocessing,
/// 10-bin softmax → MOS.
class NimaMobileNetAestheticConfig extends ModelConfig {
  const NimaMobileNetAestheticConfig();

  @override
  String get name => 'NIMA Aesthetic';

  @override
  String get path => 'assets/models/nima_mobilenet_aesthetic.onnx';

  @override
  PreprocessConfig get preprocess => PreprocessConfig.nimaMobileNet;

  @override
  OutputKind get output => OutputKind.nimaDistribution;
}
