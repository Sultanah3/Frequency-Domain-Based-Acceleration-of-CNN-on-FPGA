function write_mif(filename, data_array, width, depth)
    fid = fopen(filename, 'w');
    fprintf(fid, 'WIDTH=%d;\n', width);
    fprintf(fid, 'DEPTH=%d;\n', depth);
    fprintf(fid, 'ADDRESS_RADIX=HEX;\n');
    fprintf(fid, 'DATA_RADIX=HEX;\n');
    fprintf(fid, 'CONTENT BEGIN\n');
    
    for i = 1:numel(data_array)
        fprintf(fid, '   %X : %02X;\n', i-1, data_array(i));
    end
    
    fprintf(fid, 'END;\n');
    fclose(fid);
end