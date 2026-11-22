// Usage: node --import ./scripts/register-ts.mjs --test ...
import { register } from 'node:module';

register('./ts-loader.mjs', import.meta.url);
