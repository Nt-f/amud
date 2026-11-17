#!/usr/bin/env python3
"""`ketos segtrain` with one fix: ketos 7.1.1 passes the -bl/-tl switch on
as a string ('False'), and setup() then looks it up in a dict keyed by
booleans when the loaded model's setting differs, and fails. The string is
turned back into the boolean before setup runs. Same arguments as ketos:

    build/daf/kraken-venv/bin/python tool/daf/segtrain.py -d cuda:0 segtrain ...
"""
import sys

from kraken.train import blla

_setup = blla.BLLASegmentationModel.setup


def setup(self, stage=None):
    dc = self.trainer.datamodule.hparams.data_config
    if isinstance(dc.topline, str):
        dc.topline = {'True': True, 'False': False, 'None': None}.get(dc.topline, dc.topline)
    return _setup(self, stage)


blla.BLLASegmentationModel.setup = setup

from kraken.ketos import cli  # noqa: E402

sys.exit(cli())
