import '../output_decoder.dart';
import '../preprocessing.dart';
import 'model_config.dart';

/// NIMA MobileNet technical-quality head — same I/O shape as the aesthetic
/// variant (NHWC `[1, 224, 224, 3]` input), different weights.
class NimaMobileNetTechnicalConfig extends ModelConfig {
  const NimaMobileNetTechnicalConfig();

  @override
  String get name => 'NIMA Technical';

  @override
  String get path => 'assets/models/nima_mobilenet_technical.onnx';

  @override
  PreprocessConfig get preprocess => PreprocessConfig.nimaMobileNetNhwc;

  @override
  OutputKind get output => OutputKind.nimaDistribution;
}
