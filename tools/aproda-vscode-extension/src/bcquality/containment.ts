import * as fs from "fs/promises";
import * as path from "path";

export interface ContainmentResult {
    readonly ok: boolean;
    readonly absolutePath?: string;
    readonly reason?: string;
}

// Resolve-then-verify, never string-match: mixed separators and ".." are normalised by path.resolve, and
// realpath is checked afterwards so a symlink planted inside the clone cannot walk the result back out.
export async function resolveContained(root: string, relativePath: string): Promise<ContainmentResult> {
    if (path.isAbsolute(relativePath)) {
        return { ok: false, reason: "Path must be relative to the BCQuality clone root, not absolute." };
    }

    // Explicit rejection of NTFS alternate data streams (e.g. "entry.md:hidden"): without this, such a path
    // still stays contained and is only stopped incidentally by fs.stat's ENOENT. path.win32.basename() strips
    // a bare drive prefix like "C:foo" down to "foo", so this cannot affect that already-handled case.
    if (process.platform === "win32" && path.win32.basename(relativePath).includes(":")) {
        return { ok: false, reason: "Path segment must not contain ':' (NTFS alternate data streams are not allowed)." };
    }

    const resolvedRoot = path.resolve(root);
    const candidate = path.resolve(resolvedRoot, relativePath);
    if (!isWithin(resolvedRoot, candidate)) {
        return { ok: false, reason: "Path escapes the BCQuality clone root." };
    }

    // Compare canonical paths too: a symlink inside the clone (or a case-only match on Windows) must not
    // be able to make the string check above pass while the real target sits outside the root.
    const realRoot = await safeRealpath(resolvedRoot) ?? resolvedRoot;
    const realCandidate = await safeRealpath(candidate) ?? candidate;
    if (!isWithin(realRoot, realCandidate)) {
        return { ok: false, reason: "Path escapes the BCQuality clone root." };
    }

    return { ok: true, absolutePath: candidate };
}

// Case-insensitive on Windows (its filesystem is), and always separator-boundary-aware so a sibling
// directory whose name merely starts with the root's name (e.g. "Clone-evil" next to "Clone") is rejected.
function isWithin(root: string, candidate: string): boolean {
    const normalize = process.platform === "win32" ? (value: string) => value.toLowerCase() : (value: string) => value;
    const normalizedRoot = normalize(root);
    const normalizedCandidate = normalize(candidate);
    return normalizedCandidate === normalizedRoot || normalizedCandidate.startsWith(normalizedRoot + path.sep);
}

async function safeRealpath(candidate: string): Promise<string | undefined> {
    try {
        return await fs.realpath(candidate);
    } catch {
        return undefined;
    }
}
