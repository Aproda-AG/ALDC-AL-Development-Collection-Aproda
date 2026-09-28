// The toolkit layer must never be offered before the extension that applies it: delivering the layer
// to an older extension leaves BCQuality unreachable in the project (measured, end-to-end run 1).
// Kept as its own unit so that guarantee is testable without activating the extension.
export async function sequenceStartupChecks(
    extensionCheck: Promise<void>,
    shouldRunLayerCheck: () => boolean,
    runLayerCheck: () => Promise<void>
): Promise<void> {
    await extensionCheck;
    // Evaluated after the wait, not before: the extension check can take minutes, and the interval it
    // consumed in the meantime decides whether the layer check is still due.
    if (shouldRunLayerCheck()) {
        await runLayerCheck();
    }
}
