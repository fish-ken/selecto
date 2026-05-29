import '../output_decoder.dart';
import '../preprocessing.dart';

/// Declarative description of one bundled ONNX model: where its weights
/// live, how an image is turned into its input tensor, and how its output
/// tensor is decoded into a quality score.
///
/// One subclass per model, one file per subclass (see the sibling files in
/// this directory). Each model's full input/output contract is captured in
/// exactly one place. The registry [kModelConfigs] in `model_configs.dart`
/// lists every subclass; the picker UI and the worker pool both read from
/// it (the picker shows [name]; the worker uses [preprocess] / [output]).
///
/// To add a model:
///   1. Drop its `.onnx` into `assets/models/`.
///   2. Add a [PreprocessConfig] preset (if a new layout/normalization)
///      in `../preprocessing.dart` and an [OutputKind] (if a new head) in
///      `../output_decoder.dart`.
///   3. Add a `ModelConfig` subclass file here and list it in
///      [kModelConfigs] (`model_configs.dart`).
abstract class ModelConfig {
  const ModelConfig();

  /// Human-facing label shown in the model picker dropdown.
  String get name;

  /// Path to the `.onnx` weights under `assets/models/`.
  String get path;

  /// How an image is turned into this model's input tensor.
  PreprocessConfig get preprocess;

  /// How this model's raw output tensor maps onto the 0..10 score.
  OutputKind get output;

  /// Stable identity — used for cache namespacing, equality, and as the
  /// picker's selection key. The asset path is unique per model.
  String get id => path;

  @override
  bool operator ==(Object other) => other is ModelConfig && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
