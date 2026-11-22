// Load hook (registered by register-ts.mjs) that lets `node --test` import .ts files by transpiling them with the project's
// TypeScript (no type checking; `npx tsc --noEmit` does that). Works on Node
// builds without built-in type stripping.
import { readFile } from 'node:fs/promises';
import ts from 'typescript';

export async function load(url, context, nextLoad) {
  if (!url.endsWith('.ts')) return nextLoad(url, context);

  const source = await readFile(new URL(url), 'utf8');
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
    fileName: url,
  });
  return { format: 'module', source: outputText, shortCircuit: true };
}

