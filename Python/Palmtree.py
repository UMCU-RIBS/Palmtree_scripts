"""
Functions to load Palmtree data
=====================================================



Copyright (C) 2021, Max van den Boom (Lab of Nick Ramsey, University Medical Center Utrecht, The Netherlands)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
"""
from math import floor
import numpy as np
import pandas as pd


def load_data(filepath, read_source = False):
    """
	Read the source data (.src) or pipeline data (.dat) of a Palmtree run. The source data (.src) file contains
	the data as it is received by the source module. The pipeline data (.dat) file contains the data streams that
	went into the pipeline and - if enabled - the output of the filter modules and application modules.
	
    Args:
        filepath (str):                 path (with or without file-extension) to any of the run's data files
        read_source (bool):             if set to 0, the pipeline data (.dat) will be read; 
		                                if set to 1, the source data (.src) will be read

    Returns:
        header (Dictionary):            The data header information as a struct, includes information such as the
                                        sampling rate, number of streams and stream names
        samples (ndarray):              A matrix holding the data. The first column will be the sample-number, the
                                        second column holds the number of milliseconds that have passed since the last
                                        sample, and the remaining columns represent the sample values that streamed 
                                        through the pipeline (the header information can be used to find the exact 
                                        channel(s) and where in the pipeline.
    """

    # TODO

