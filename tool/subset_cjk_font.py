"""重新產生內建中文字型（老闆 2026-10-29：現代黑體）。

App 介面新增中文字時跑一次（需要 fonttools 與思源黑體可變字型 NotoSansTC[wght].ttf，
來源 https://github.com/google/fonts/tree/main/ofl/notosanstc ，SIL OFL 授權）：

    pip install fonttools
    python3 tool/subset_cjk_font.py <NotoSansTC[wght].ttf 的路徑>

會掃 lib/ 所有字串裡的中文字，產生 assets/fonts/NotoSansTC-{Regular,Medium,Bold}.ttf。
沒收進來的字（例如資料裡的品名）App 仍會由瀏覽器補下載，只是按鈕這類元件寬度可能量不準。
"""
import glob
import re
import subprocess
import sys
import tempfile

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

EXTRA = '，。、；：？！「」『』（）《》〈〉【】…—～・／＋－×÷＝％＄＃＆＊＠　'


def ui_chars() -> str:
    chars = set(EXTRA)
    for f in glob.glob('lib/**/*.dart', recursive=True):
        s = re.sub(r'//[^\n]*', '', open(f, encoding='utf-8').read())
        for m in re.finditer(r"'([^'\\]|\\.)*'|\"([^\"\\]|\\.)*\"", s):
            chars.update(c for c in m.group(0)
                         if '　' <= c <= '鿿' or '＀' <= c <= '￯' or '⺀' <= c <= '⿿')
    return ''.join(sorted(chars))


def main(src: str) -> None:
    text = ui_chars()
    with tempfile.TemporaryDirectory() as tmp:
        open(f'{tmp}/sub.txt', 'w', encoding='utf-8').write(text)
        for weight, name in [(400, 'Regular'), (500, 'Medium'), (700, 'Bold')]:
            inst = instancer.instantiateVariableFont(TTFont(src), {'wght': weight})
            inst.save(f'{tmp}/{name}.ttf')
            subprocess.run(['pyftsubset', f'{tmp}/{name}.ttf', f'--text-file={tmp}/sub.txt', '--layout-features=*',
                            '--no-hinting', f'--output-file=assets/fonts/NotoSansTC-{name}.ttf'], check=True)
    print(f'{len(text)} 個字')


if __name__ == '__main__':
    main(sys.argv[1])
