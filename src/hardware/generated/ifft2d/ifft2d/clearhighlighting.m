SLStudio.Utils.RemoveHighlighting(get_param('ifft2d', 'handle'));
SLStudio.Utils.RemoveHighlighting(get_param('gm_ifft2d', 'handle'));
annotate_port('gm_ifft2d/ifft2d', 0, 1, '');
annotate_port('gm_ifft2d/ifft2d/FFT_core', 0, 1, '');
annotate_port('gm_ifft2d/ifft2d/RAM_B', 1, 1, '');
annotate_port('ifft2d/ifft2d/RAM_B', 1, 1, '');
annotate_port('gm_ifft2d/ifft2d/XNOR_weB', 1, 1, '');
annotate_port('ifft2d/ifft2d/XNOR_weB', 1, 1, '');
