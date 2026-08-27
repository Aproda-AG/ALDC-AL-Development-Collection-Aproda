import { spawn } from "child_process";

export interface ProcessResult {
    readonly code: number;
    readonly stdout: string;
    readonly stderr: string;
}

export function run(command: string, args: readonly string[], options: { cwd?: string; env?: NodeJS.ProcessEnv } = {}): Promise<ProcessResult> {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, {
            cwd: options.cwd,
            env: { ...process.env, ...options.env },
            windowsHide: true
        });
        let stdout = "";
        let stderr = "";

        child.stdout.setEncoding("utf8");
        child.stderr.setEncoding("utf8");
        child.stdout.on("data", (chunk: string) => { stdout += chunk; });
        child.stderr.on("data", (chunk: string) => { stderr += chunk; });
        child.on("error", reject);
        child.on("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
    });
}
