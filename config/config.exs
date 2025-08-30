import Config

config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "pdf_screenplay_parsex"
  version = "0.1.0"
  requires-python = ">=3.11"
  dependencies = [
    "PyMuPDF==1.26.4",
    "langdetect==1.0.9",
    "spacy>=3.8.0"
  ]
  """