export function compareExtensionVersions(left: string, right: string): number {
    const leftVersion = parseVersion(left);
    const rightVersion = parseVersion(right);
    for (let index = 0; index < 3; index += 1) {
        const difference = leftVersion.core[index] - rightVersion.core[index];
        if (difference !== 0) {
            return difference < 0 ? -1 : 1;
        }
    }
    if (!leftVersion.prerelease || !rightVersion.prerelease) {
        return leftVersion.prerelease ? -1 : rightVersion.prerelease ? 1 : 0;
    }
    const length = Math.max(leftVersion.prerelease.length, rightVersion.prerelease.length);
    for (let index = 0; index < length; index += 1) {
        const leftIdentifier = leftVersion.prerelease[index];
        const rightIdentifier = rightVersion.prerelease[index];
        if (leftIdentifier === undefined || rightIdentifier === undefined) {
            return leftIdentifier === undefined ? -1 : 1;
        }
        if (leftIdentifier === rightIdentifier) {
            continue;
        }
        const leftNumber = /^\d+$/.test(leftIdentifier);
        const rightNumber = /^\d+$/.test(rightIdentifier);
        if (leftNumber && rightNumber) {
            return Number(leftIdentifier) < Number(rightIdentifier) ? -1 : 1;
        }
        if (leftNumber !== rightNumber) {
            return leftNumber ? -1 : 1;
        }
        return leftIdentifier < rightIdentifier ? -1 : 1;
    }
    return 0;
}

function parseVersion(version: string): { core: number[]; prerelease?: string[] } {
    const [withoutBuild] = version.split("+");
    const [core, prerelease] = withoutBuild.split("-", 2);
    return { core: core.split(".").map(Number), prerelease: prerelease?.split(".") };
}