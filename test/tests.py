#/usr/bin/env python3

import numpy
numpy.test('full')

import scipy
scipy.test('full')

import pytest
pytest.main(["pandas"])
