"""llvm-cov report çıktısında bir modülün satır kapsamını eşiğe göre denetler.

Kullanım: python3 -I scripts/coverage_gate.py <rapor.txt> <modül-yolu-parçası> <eşik-yüzde>
Rapor satırları (llvm-cov report) sütunları:
  0: dosya  1: Regions  2: Missed  3: Cover%  4: Functions  5: Missed  6: Cover%
  7: Lines  8: Missed Lines  9: Cover%  ...
Bu araç 7 (toplam satır) ve 8 (kaçırılan satır) sütunlarını toplar.
"""
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("kullanım: coverage_gate.py <rapor> <modül> <eşik>", file=sys.stderr)
        return 2
    report, module, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])
    # llvm-cov report ortak öneki kırpar; yollar "NobetciCore/..." biçiminde gelir
    # (Sources/ öneki olmadan). Modül adı + "/" ile eşle.
    needle = f"{module}/"
    covered = total = 0
    for line in open(report, encoding="utf-8"):
        if needle not in line:
            continue
        cols = line.split()
        try:
            lines_total, lines_missed = int(cols[7]), int(cols[8])
        except (IndexError, ValueError):
            continue
        total += lines_total
        covered += lines_total - lines_missed
    if total == 0:
        print(f"{module}: kapsam raporunda satır bulunamadı", file=sys.stderr)
        return 1
    pct = 100.0 * covered / total
    print(f"{module} satır kapsamı: {pct:.1f}% (eşik {threshold}%)")
    return 0 if pct >= threshold else 1


if __name__ == "__main__":
    sys.exit(main())
