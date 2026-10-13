"""Bundle the checked-out dependencies' license and notice texts with the app."""
from pathlib import Path
import shutil
import sys
import stat

def copy_license(source, destination):
    if destination.exists():
        destination.chmod(destination.stat().st_mode | stat.S_IWUSR)
    shutil.copy2(source, destination)

target = Path(sys.argv[1])
target.mkdir(parents=True, exist_ok=True)
vendored_names = {p.name for p in Path('Vendor').iterdir() if p.is_dir()}
for package in sorted(Path('.build/checkouts').iterdir()):
    if package.name in vendored_names:
        continue
    for source in package.iterdir():
        if source.is_file() and source.name.lower().startswith(('license', 'copying', 'notice')):
            destination = target / package.name
            destination.mkdir(exist_ok=True)
            copy_license(source, destination / source.name)
for package in sorted(Path('Vendor').iterdir()):
    for source in package.iterdir():
        if source.is_file() and source.name.lower().startswith(('license', 'copying', 'notice', 'upstream')):
            destination = target / package.name
            destination.mkdir(exist_ok=True)
            copy_license(source, destination / source.name)
# Native MLX embeds these attributed C/C++ components in its static library.
mlx_sources = Path('Vendor/mlx-swift/Source/Cmlx')
if mlx_sources.is_dir():
    for source in sorted(mlx_sources.rglob('*')):
        if source.is_file() and source.name.lower().startswith(('license', 'copying', 'notice')):
            destination = target / 'mlx-swift-components' / source.parent.relative_to(mlx_sources)
            destination.mkdir(parents=True, exist_ok=True)
            copy_license(source, destination / source.name)
