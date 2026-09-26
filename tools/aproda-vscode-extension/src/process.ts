import { spawn } from "child_process";

export interface ProcessResult {
    readonly code: number;
    readonly stdout: string;
    readonly stderr: string;
}

// VS Code's extension host runs with NODE_TLS_REJECT_UNAUTHORIZED=0 and verifies certificates itself.
// That only protects the host: a spawned Node process inherits the variable and silently stops checking
// certificates -- which would let `npm install` fetch packages over an unverified connection.
export function childEnvironment(): NodeJS.ProcessEnv {
    const { NODE_TLS_REJECT_UNAUTHORIZED: _stripped, ...rest } = process.env;
    return rest;
}

export function run(command: string, args: readonly string[], options: { cwd?: string; env?: NodeJS.ProcessEnv; shell?: boolean } = {}): Promise<ProcessResult> {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, {
            cwd: options.cwd,
            env: { ...childEnvironment(), ...options.env },
            // Opt-in per call, never the default: under a shell the arguments stop being quoted for the
            // callee, so only a caller passing nothing user-influenced may ask for it.
            shell: options.shell === true,
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
