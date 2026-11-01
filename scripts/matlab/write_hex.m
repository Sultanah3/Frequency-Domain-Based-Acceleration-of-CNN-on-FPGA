function write_hex(filename, data_array, width)
% Writes one value per line in hex, two's complement on 'width' bits, for Verilog $readmemh.
    fid = fopen(filename, 'w');
    fprintf(fid, sprintf('%%0%dX\\n', ceil(width/4)), mod(double(data_array(:)), 2^width));
    fclose(fid);
end