"""Fetch the pinned official macOS 15 MLX shader library for release builds."""
from pathlib import Path
import hashlib
import shutil
import sys
import urllib.request
import zipfile

URL = 'https://files.pythonhosted.org/packages/4f/5d/4c690d5b93c30ba002656c37363159d978705bf8eb801b8481840fb942c2/mlx_metal-0.31.2-py3-none-macosx_15_0_arm64.whl'
SHA256 = 'e9d4e5fce6ca10a87a0e388597f99519ad594d09e674708b5312bd8bd4f5997d'
cache = Path('.build/downloads/mlx_metal-0.31.2-macosx_15_0_arm64.whl')
cache.parent.mkdir(parents=True, exist_ok=True)

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

if not cache.exists() or digest(cache) != SHA256:
    temporary = cache.with_suffix('.download')
    try:
        with urllib.request.urlopen(URL, timeout=120) as source, temporary.open('wb') as output:
            shutil.copyfileobj(source, output)
        if digest(temporary) != SHA256:
            raise SystemExit('The MLX runtime download failed checksum verification.')
        temporary.replace(cache)
    finally:
        temporary.unlink(missing_ok=True)

destination = Path(sys.argv[1])
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(cache) as archive:
    candidates = [name for name in archive.namelist() if name.endswith('/mlx.metallib')]
    if len(candidates) != 1:
        raise SystemExit('The MLX runtime archive has an unexpected layout.')
    with archive.open(candidates[0]) as source, destination.open('wb') as output:
        shutil.copyfileobj(source, output)
print('Bundled the checksum-verified MLX 0.31.2 shader runtime for macOS 15+.')
