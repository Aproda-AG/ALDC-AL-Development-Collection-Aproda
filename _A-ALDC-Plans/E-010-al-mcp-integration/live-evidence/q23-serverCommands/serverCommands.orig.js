"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ownStartPathConfirmed = exports.ownServerIdCandidate = void 0;
exports.startOwnServer = startOwnServer;
exports.restartOwnServer = restartOwnServer;
const vscode = __importStar(require("vscode"));
// TODO(Q-23): the argument VS Code expects for `workbench.mcp.startServer` / `workbench.mcp.restartServer` for a
// provider-registered server is not measured yet (E-010 spec §4.9). This is a GUESS (provider id + "/" + label).
// Measure with a scratch command, record the accepted form in E-010-plan.md, then change ONLY this constant and
// flip `ownStartPathConfirmed`. The server id must never come from the model or from user input.
exports.ownServerIdCandidate = "aprodaAldc.alMcp/al-mcp";
// Doctor input (spec §4.8): false while Q-23 is open, so `auto` + `chat.mcp.autostart = never` is reported.
exports.ownStartPathConfirmed = false;
// workbench.mcp.startServer resolves without telling whether a server with that id exists, so "started" means
// "the command was issued", not "the server is running".
async function startOwnServer(logger) {
    try {
        await vscode.commands.executeCommand("workbench.mcp.startServer", exports.ownServerIdCandidate);
        return "started";
    }
    catch (error) {
        logger.error(`workbench.mcp.startServer failed for '${exports.ownServerIdCandidate}' (Q-23): ${error instanceof Error ? error.message : String(error)}`);
        return "failed";
    }
}
async function restartOwnServer(logger) {
    try {
        await vscode.commands.executeCommand("workbench.mcp.restartServer", exports.ownServerIdCandidate);
        return "restarted";
    }
    catch (error) {
        logger.error(`workbench.mcp.restartServer failed for '${exports.ownServerIdCandidate}' (Q-23): ${error instanceof Error ? error.message : String(error)}`);
        return "failed";
    }
}
