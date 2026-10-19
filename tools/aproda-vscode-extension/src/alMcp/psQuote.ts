// PowerShell single-quoted literal. Besides `'`, PowerShell also treats U+2018/U+2019/U+201A/U+201B as quote
// characters, so a path containing one would otherwise end the literal early.
export function psQuote(value: string): string {
    return `'${value.replace(/['\u2018\u2019\u201A\u201B]/g, (character) => character + character)}'`;
}
