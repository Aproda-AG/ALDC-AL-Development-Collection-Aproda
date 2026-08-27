import * as fs from "fs/promises";
import * as path from "path";

export async function proposeDevRoot(repositoryRoot: string | undefined): Promise<string | undefined> {
    if (!repositoryRoot) {
        return undefined;
    }
    const parsed = path.parse(repositoryRoot);
    const relativeParts = path.relative(parsed.root, repositoryRoot).split(path.sep).filter(Boolean);
    const candidate = relativeParts.length > 0 ? path.join(parsed.root, relativeParts[0]) : path.dirname(repositoryRoot);
    return await directoryExists(candidate) && path.resolve(candidate) !== path.resolve(repositoryRoot)
        ? candidate
        : path.dirname(repositoryRoot);
}

export async function directoryExists(candidate: string): Promise<boolean> {
    try {
        return (await fs.stat(candidate)).isDirectory();
    } catch {
        return false;
    }
}