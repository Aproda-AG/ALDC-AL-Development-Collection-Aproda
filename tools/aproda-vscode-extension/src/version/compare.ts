export type VersionComparison = -1 | 0 | 1 | undefined;

const versionPattern = /^(\d+)\.(\d+)\.(\d+)_aproda\.(\d+)$/;

export function compareLayerVersions(left: string, right: string): VersionComparison {
    const leftParts = parse(left);
    const rightParts = parse(right);
    if (!leftParts || !rightParts) {
        return undefined;
    }
    for (let index = 0; index < leftParts.length; index += 1) {
        if (leftParts[index] !== rightParts[index]) {
            return leftParts[index] < rightParts[index] ? -1 : 1;
        }
    }
    return 0;
}

export function isLayerVersion(value: string): boolean {
    return parse(value) !== undefined;
}

function parse(value: string): number[] | undefined {
    const match = versionPattern.exec(value);
    return match?.slice(1).map(Number);
}
