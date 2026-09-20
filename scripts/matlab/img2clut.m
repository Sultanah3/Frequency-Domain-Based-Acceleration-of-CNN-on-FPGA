function generate_verilog_hex(image_path, options)
    % GENERATE_VERILOG_HEX Uses Python Pillow via MATLAB to generate 100% identical HEX files.
    
    arguments
        image_path (1,1) string {mustBeFile}
        options.output_dir (1,1) string = "."
        options.num_colors (1,1) double {mustBePositive, mustBeInteger} = 256
        options.target_size (1,2) double {mustBePositive, mustBeInteger} = [128, 128]
    end

    [~, base_name, ~] = fileparts(image_path);
    
    % Ensure output directory exists
    if ~exist(options.output_dir, 'dir')
        mkdir(options.output_dir);
    end

    % Format output file paths
    index_hex_path = fullfile(options.output_dir, sprintf('%s_index_map.hex', base_name));
    palette_hex_path = fullfile(options.output_dir, sprintf('%s_color_map.hex', base_name));

    % 1. Import Python PIL library inside MATLAB
    PIL_Image = py.importlib.import_module('PIL.Image');

    % 2. Open and convert image to RGB using Pillow
    img = PIL_Image.open(image_path).convert('RGB');

    % 3. Resize image using Lanczos
    target_tuple = py.tuple({int64(options.target_size(1)), int64(options.target_size(2))});
    if ~isequal(double(img.size), options.target_size)
        img = img.resize(target_tuple, PIL_Image.Resampling.LANCZOS);
    end

    % 4. Quantize using Pillow's exact MEDIANCUT algorithm
    quantized_img = img.quantize(int64(options.num_colors), PIL_Image.Quantize.MEDIANCUT);

    % 5. Extract Index Map & Palette back into MATLAB
    % Convert PyObject bytes/arrays to MATLAB numeric arrays
    index_bytes = uint8(py.array.array('B', quantized_img.tobytes()));
    
    palette_raw = uint8(py.array.array('B', quantized_img.getpalette()));
    palette_rgb = reshape(palette_raw(1:options.num_colors*3), 3, [])';

    % 6. Write Index Map to .hex
    fid_index = fopen(index_hex_path, 'w');
    if fid_index == -1, error('Failed to create file: %s', index_hex_path); end
    fprintf(fid_index, '%02X\n', index_bytes);
    fclose(fid_index);

    % 7. Write Color Map (Palette) to .hex
    fid_palette = fopen(palette_hex_path, 'w');
    if fid_palette == -1, error('Failed to create file: %s', palette_hex_path); end
    
    r = uint32(palette_rgb(:, 1));
    g = uint32(palette_rgb(:, 2));
    b = uint32(palette_rgb(:, 3));
    
    hex_colors = bitshift(r, 16) + bitshift(g, 8) + b;
    fprintf(fid_palette, '%06X\n', hex_colors);
    fclose(fid_palette);

    % Print confirmation
    [~, input_filename, ext] = fileparts(image_path);
    fprintf('Successfully processed ''%s%s'':\n', input_filename, ext);
    fprintf('   - Index Map  : ''%s'' (%d entries)\n', index_hex_path, numel(index_bytes));
    fprintf('   - Color Map  : ''%s'' (%d entries)\n', palette_hex_path, size(palette_rgb, 1));
end