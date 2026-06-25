# The live model test downloads a Hugging Face model (network, ~90MB); excluded
# by default. Run with: mix test --include bumblebee
ExUnit.start(exclude: [:bumblebee])
