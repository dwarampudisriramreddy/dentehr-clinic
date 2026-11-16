AI models are **not bundled**. The app loads a model you pick from device storage.

- Use a LiteRT-LM `.litertlm` model (e.g. Gemma 4 E2B / Qwen3 0.6B `.litertlm`).
- In the odontogram screen, tap **Pick model** and select the `.litertlm` file from internal/storage.
- The selected file path is installed via `flutter_edge_ai` (`fromFile`) and used for chart/diagnosis prompts.
