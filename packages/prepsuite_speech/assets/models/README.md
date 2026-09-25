Model files live here but are not in git. Recreate them with:

    tools/voice/fetch_models.sh

The folders are declared as assets in ../../pubspec.yaml and kept in git by
.gitkeep files, so builds work without the models (the app then offers typing).
