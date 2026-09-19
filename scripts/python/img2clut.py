import argparse
from pathlib import Path
import numpy as np
from PIL import Image


def generate_verilog_hex(
    image_path: str,
    output_dir: str = ".",
    num_colors: int = 256,
    target_size: tuple[int, int] = (128, 128),
) -> None:
    img_path = Path(image_path)
    out_dir = Path(output_dir)

    # Extract base filename without extension (e.g., 'input.png' -> 'input')
    base_name = img_path.stem

    # Ensure output directory exists
    out_dir.mkdir(parents=True, exist_ok=True)

    # Format output filenames: <filename>_index_map.hex and <filename>_color_map.hex
    index_hex_path = out_dir / f"{base_name}_index_map.hex"
    palette_hex_path = out_dir / f"{base_name}_color_map.hex"

    # 1. Load and resize image to target dimensions (128x128)
    img = Image.open(img_path).convert("RGB")
    if img.size != target_size:
        img = img.resize(target_size, Image.Resampling.LANCZOS)

    # 2. Quantize image using adaptive palette (MEDIANCUT)
    quantized_img = img.quantize(colors=num_colors, method=Image.Quantize.MEDIANCUT)

    # 3. Extract Index Map (128x128 8-bit integers)
    index_map = np.array(quantized_img, dtype=np.uint8)

    # 4. Extract Palette (List of [R, G, B] values)
    palette_raw = quantized_img.getpalette()[: num_colors * 3]
    palette_rgb = np.array(palette_raw, dtype=np.uint8).reshape(-1, 3)

    # 5. Export Index Map to .hex (16,384 lines of 2-digit hex)
    with open(index_hex_path, "w") as f_index:
        for val in index_map.flatten():
            f_index.write(f"{val:02X}\n")

    # 6. Export Color Map to .hex (256 lines of 6-digit RRGGBB hex)
    with open(palette_hex_path, "w") as f_palette:
        for r, g, b in palette_rgb:
            hex_color = (int(r) << 16) | (int(g) << 8) | int(b)
            f_palette.write(f"{hex_color:06X}\n")

    print(f"Successfully processed '{img_path.name}':")
    print(f"  - Index Map  : '{index_hex_path}' ({index_map.size} entries, 8-bit)")
    print(
        f"  - Color Map  : '{palette_hex_path}' ({len(palette_rgb)} entries, 24-bit RGB)"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Convert an image to prefixed Index Map and Color Map HEX files for Verilog $readmemh."
    )
    parser.add_argument(
        "-i", "--input", required=True, type=str, help="Path to the input PNG/JPG image"
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=str,
        default=".",
        help="Target directory to save .hex files (default: current directory)",
    )

    args = parser.parse_args()
    generate_verilog_hex(image_path=args.input, output_dir=args.output_dir)


if __name__ == "__main__":
    main()
