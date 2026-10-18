#!/usr/bin/env node
// Read-only Khronos validation for source glTFs, including their local external resources.
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const require = createRequire(import.meta.url);
const validator = require('gltf-validator');
const packageInfo = require('./node_modules/gltf-validator/package.json');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EXPECTED_VALIDATOR = '2.0.0-dev.3.10';
const DEFAULT_INPUTS = [
	'app/assets/landscape/vegetation/models/CommonTree_1.gltf',
	'app/assets/landscape/vegetation/models/CommonTree_2.gltf',
	'app/assets/landscape/vegetation/models/CommonTree_3.gltf',
	'app/assets/landscape/vegetation/models/CommonTree_4.gltf',
	'app/assets/landscape/vegetation/models/Pine_1.gltf',
	'app/assets/landscape/vegetation/models/Pine_2.gltf',
	'app/assets/landscape/vegetation/models/Pine_3.gltf',
	'assets/landscape/vegetation/source/polyhaven_pine_sapling_small/pine_sapling_small_1k.gltf',
];

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const requireThat = (ok, message) => { if (!ok) throw new Error(message); };

function parseArgs(argv) {
	let out = '';
	const inputs = [];
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === '--out') {
			requireThat(i + 1 < argv.length, 'Missing value after --out');
			out = argv[++i];
		} else if (arg.startsWith('--out=')) {
			out = arg.slice('--out='.length);
		} else if (arg.startsWith('--')) {
			throw new Error(`Unknown option: ${arg}`);
		} else {
			inputs.push(arg);
		}
	}
	requireThat(out.length > 0, 'Usage: node tools/trees/validate_sources.mjs --out REPORT.json [GLTF ...]');
	return {out: path.resolve(out), inputs: inputs.length > 0 ? inputs : DEFAULT_INPUTS};
}

function inside(base, target) {
	const relative = path.relative(base, target);
	return relative === '' || (!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`));
}

function repoRelative(filePath) {
	return path.relative(root, filePath).split(path.sep).join('/');
}

function resourceRoles(document) {
	const roles = new Map();
	for (const [key, role] of [['buffers', 'buffer'], ['images', 'image']]) {
		for (const item of document[key] ?? []) {
			if (!item.uri) continue;
			const roleSet = roles.get(item.uri) ?? new Set();
			roleSet.add(role);
			roles.set(item.uri, roleSet);
		}
	}
	return roles;
}

function decodeLocalResource(documentPath, uri) {
	const withoutSuffix = uri.split(/[?#]/, 1)[0];
	requireThat(withoutSuffix.length > 0, `Empty external resource URI in ${repoRelative(documentPath)}`);
	let decoded;
	try {
		decoded = decodeURIComponent(withoutSuffix);
	} catch (error) {
		throw new Error(`Invalid percent-encoded URI ${JSON.stringify(uri)} in ${repoRelative(documentPath)}: ${error.message}`);
	}
	requireThat(!/^[A-Za-z][A-Za-z\d+.-]*:/.test(decoded), `Non-local external URI ${JSON.stringify(uri)} in ${repoRelative(documentPath)}`);
	requireThat(!decoded.startsWith('/') && !decoded.startsWith('\\') && !/^[A-Za-z]:/.test(decoded),
		`Absolute external URI ${JSON.stringify(uri)} in ${repoRelative(documentPath)}`);
	const localPath = decoded.replace(/[\\/]/g, path.sep);
	const resolved = path.resolve(path.dirname(documentPath), localPath);
	requireThat(inside(root, resolved), `External URI escapes repository root: ${JSON.stringify(uri)} in ${repoRelative(documentPath)}`);
	return resolved;
}

function addSourceFile(sourceFiles, filePath, bytes, role, referencedBy = null, uri = null) {
	const normalizedPath = path.resolve(filePath);
	let item = sourceFiles.get(normalizedPath);
	if (!item) {
		item = {
			path: repoRelative(normalizedPath),
			bytes: bytes.byteLength,
			sha256: sha256(bytes),
			roles: [],
			references: [],
		};
		sourceFiles.set(normalizedPath, item);
	}
	if (!item.roles.includes(role)) item.roles.push(role);
	if (referencedBy) {
		const reference = {document: repoRelative(referencedBy), uri};
		if (!item.references.some(existing => existing.document === reference.document && existing.uri === reference.uri)) {
			item.references.push(reference);
		}
	}
	return item;
}

function severityName(severity) {
	return ['error', 'warning', 'information', 'hint'][severity] ?? `severity_${severity}`;
}

function disposition(severity) {
	if (severity === 0) return 'blocking: zero validator errors are required';
	if (severity === 1) return 'review listed warning; source bytes were left unchanged';
	return 'informational validator note; source bytes were left unchanged';
}

function compactIssues(report) {
	const groups = new Map();
	for (const issue of report.issues.messages) {
		const key = `${issue.severity}\u0000${issue.code}\u0000${issue.pointer ?? ''}`;
		let group = groups.get(key);
		if (!group) {
			group = {
				severity: issue.severity,
				level: severityName(issue.severity),
				code: issue.code,
				pointer: issue.pointer ?? '',
				disposition: disposition(issue.severity),
				count: 0,
				examples: [],
			};
			groups.set(key, group);
		}
		group.count++;
		if (group.examples.length < 5 && !group.examples.includes(issue.message)) group.examples.push(issue.message);
	}
	const messages = [...groups.values()].sort((a, b) => a.severity - b.severity || a.code.localeCompare(b.code) || a.pointer.localeCompare(b.pointer));
	const countsByCode = {};
	for (const group of messages) countsByCode[group.code] = (countsByCode[group.code] ?? 0) + group.count;
	return {
		numErrors: report.issues.numErrors,
		numWarnings: report.issues.numWarnings,
		numInfos: report.issues.numInfos,
		numHints: report.issues.numHints,
		messageCount: report.issues.messages.length,
		countsByCode,
		messages,
	};
}

async function validateOne(input, sourceFiles) {
	const filePath = path.resolve(input);
	requireThat(inside(root, filePath), `Input must be inside repository: ${input}`);
	requireThat(path.extname(filePath).toLowerCase() === '.gltf', `Expected a JSON .gltf input: ${input}`);
	const bytes = await fs.readFile(filePath);
	const text = bytes.toString('utf8').replace(/^\uFEFF/, '');
	const assetRecord = addSourceFile(sourceFiles, filePath, bytes, 'gltf');
	const base = {
		path: repoRelative(filePath),
		bytes: bytes.byteLength,
		sha256: assetRecord.sha256,
		dependencies: [],
		validation: null,
	};
	let document;
	try {
		document = JSON.parse(text);
	} catch (error) {
		base.validation = {status: 'failed', error: `Invalid JSON: ${error.message}`};
		return base;
	}
	const roles = resourceRoles(document);
	const resourceRecords = new Map();
	const resourceLoadErrors = [];
	const contentCache = new Map();
	let validation;
	try {
		validation = await validator.validateString(text, {
			uri: repoRelative(filePath),
			maxIssues: 0,
			writeTimestamp: false,
			externalResourceFunction: async uri => {
				try {
					const resolved = decodeLocalResource(filePath, uri);
					let content = contentCache.get(resolved);
					if (!content) {
						content = await fs.readFile(resolved);
						contentCache.set(resolved, content);
					}
					const roleSet = roles.get(uri) ?? new Set(['external resource']);
					const sourceRecord = addSourceFile(sourceFiles, resolved, content, 'external resource', filePath, uri);
					for (const role of roleSet) addSourceFile(sourceFiles, resolved, content, role, filePath, uri);
					resourceRecords.set(uri, {
						uri,
						path: repoRelative(resolved),
						bytes: content.byteLength,
						sha256: sourceRecord.sha256,
						roles: [...roleSet],
						loaded: true,
					});
					return new Uint8Array(content.buffer, content.byteOffset, content.byteLength);
				} catch (error) {
					resourceLoadErrors.push({uri, error: error.message});
					throw error;
				}
			},
		});
		base.validation = {
			status: 'validated',
			validatorVersion: validation.validatorVersion,
			issues: compactIssues(validation),
		};
	} catch (error) {
		base.validation = {
			status: 'failed',
			error: String(error),
		};
	}
	base.dependencies = [...resourceRecords.values()].sort((a, b) => a.uri.localeCompare(b.uri));
	base.resourceLoadErrors = resourceLoadErrors;
	if (base.validation.status === 'validated') {
		base.validation.ok = base.validation.issues.numErrors === 0 && resourceLoadErrors.length === 0;
	}
	return base;
}

async function main() {
	requireThat(packageInfo.version === EXPECTED_VALIDATOR, `Expected pinned gltf-validator ${EXPECTED_VALIDATOR}; found ${packageInfo.version}`);
	requireThat(validator.version() === EXPECTED_VALIDATOR, `Validator reports unexpected version ${validator.version()}`);
	const {out, inputs} = parseArgs(process.argv.slice(2));
	await fs.mkdir(path.dirname(out), {recursive: true});
	try {
		await fs.access(out);
		throw new Error(`Report already exists; choose a new --out path: ${out}`);
	} catch (error) {
		if (error.code !== 'ENOENT') throw error;
	}

	const sourceFiles = new Map();
	const assets = [];
	for (const input of inputs) assets.push(await validateOne(input, sourceFiles));
	const numErrors = assets.reduce((sum, asset) => sum + (asset.validation?.issues?.numErrors ?? 1), 0);
	const numWarnings = assets.reduce((sum, asset) => sum + (asset.validation?.issues?.numWarnings ?? 0), 0);
	const unresolvedResources = assets.reduce((sum, asset) => sum + (asset.resourceLoadErrors?.length ?? 0), 0);
	const failedAssets = assets.filter(asset => asset.validation?.status !== 'validated' || !asset.validation?.ok);
	const result = {
		format: 'openrc-gltf-source-validation v1',
		result: failedAssets.length > 0 ? 'failed' : (numWarnings > 0 ? 'passed_with_warnings' : 'passed'),
		generatedAt: new Date().toISOString(),
		tools: {
			validator: 'Khronos glTF Validator',
			package: 'gltf-validator',
			pinnedPackageVersion: packageInfo.version,
			validatorVersion: validator.version(),
			node: process.version,
		},
		scope: 'Read-only validation of original JSON glTF files plus locally referenced external buffers/images. No source file was modified.',
		disposition: {
			errorGate: 'Every input must report zero validator errors and load every external resource.',
			warnings: 'All warnings are retained with code, message, pointer, and review disposition; none are suppressed.',
			limitations: 'Khronos format validation does not establish Godot import success, visual quality, runtime suitability, or performance.',
		},
		summary: {
			assets: assets.length,
			errors: numErrors,
			warnings: numWarnings,
			unresolvedResources,
			passed: failedAssets.length === 0,
		},
		assets,
		sourceFiles: [...sourceFiles.values()].sort((a, b) => a.path.localeCompare(b.path)),
	};
	await fs.writeFile(out, `${JSON.stringify(result, null, 2)}\n`, {flag: 'wx'});
	console.log(JSON.stringify({report: repoRelative(out), ...result.summary, result: result.result}));
	if (!result.summary.passed) process.exitCode = 1;
}

main().catch(error => {
	console.error(error);
	process.exitCode = 1;
});
