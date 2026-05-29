import '../output_decoder.dart';
import '../preprocessing.dart';
import 'model_config.dart';

/// NIMA MobileNet aesthetic head — 224×224 NHWC, MobileNet preprocessing,
/// 10-bin softmax → MOS. (This export's input tensor is `[1, 224, 224, 3]`
/// — NHWC, not NCHW; ORT rejects the wrong layout outright.)
class NimaMobileNetAestheticConfig extends ModelConfig {
  const NimaMobileNetAestheticConfig();

  @override
  String get name => 'NIMA Aesthetic';

  @override
  String get path => 'assets/models/nima_mobilenet_aesthetic.onnx';

  @override
  PreprocessConfig get preprocess => PreprocessConfig.nimaMobileNetNhwc;

  @override
  OutputKind get output => OutputKind.nimaDistribution;
}
