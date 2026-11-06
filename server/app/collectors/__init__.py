from . import applyhome, gh, lh, sh

COLLECTORS = {"LH": lh.collect, "SH": sh.collect, "GH": gh.collect, "APPLYHOME": applyhome.collect}
