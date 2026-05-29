import '../output_decoder.dart';
import '../preprocessing.dart';
import 'model_config.dart';

/// MANIQA trained on KADID-10K — 224×224 NCHW, ImageNet normalization,
/// single sigmoid quality scalar.
class Maniqa10kConfig extends ModelConfig {
  const Maniqa10kConfig();

  @override
  String get name => 'MANIQA (KADID-10K)';

  @override
  String get path => 'assets/models/maniqa_kadid10k.onnx';

  @override
  PreprocessConfig get preprocess => PreprocessConfig.maniqaImageNet;

  @override
  OutputKind get output => OutputKind.scalarSigmoid;
}
