#!/usr/bin/env node
/**
 * 版本一致性檢查工具
 * 驗證 CLI UA 版本、axios 版本、stainless SDK 版本之間的對應關係是否合理
 *
 * 用法:
 *   node version-consistency-check.js --cli "claude-cli/2.1.81 (external, cli)" --axios "axios/1.13.6"
 *   node version-consistency-check.js --headers '{"user-agent":"claude-cli/2.1.22","x-stainless-package-version":"0.70.0"}'
 */

// 已知的版本對應表（從實測數據）
const VERSION_MAP = {
    // Claude Code version → expected axios version
    axios: {
        '1.0.3': '1.8.4',
        '1.0.6': '1.8.4',
        '1.0.8': '1.8.4',
        '1.0.16': '1.8.4',
        '1.0.18': '1.8.4',
        '2.0.0': '1.8.4',
        '2.0.2': '1.8.4',
        '2.0.5': '1.8.4',
        '2.1.0': '1.8.4',
        '2.1.10': '1.8.4',
        '2.1.22': '1.8.4',
        '2.1.44': '1.8.4',
        '2.1.67': '1.8.4',
        '2.1.72': '1.8.4',
        '2.1.78': '1.13.4',
        '2.1.80': '1.13.6',
        '2.1.81': '1.13.6',
        '2.1.83': '1.13.6',
        '2.1.85': '1.13.6',
        '2.1.87': '1.13.6',
    }
};

// axios 版本分段
const AXIOS_RANGES = [
    { axiosVer: '1.8.4', cliMin: '1.0.3', cliMax: '2.1.72' },
    { axiosVer: '1.13.4', cliMin: '2.1.78', cliMax: '2.1.78' },
    { axiosVer: '1.13.6', cliMin: '2.1.80', cliMax: '99.99.99' },
];

function parseVersion(v) {
    const match = v.match(/(\d+)\.(\d+)\.(\d+)/);
    if (!match) return null;
    return { major: parseInt(match[1]), minor: parseInt(match[2]), patch: parseInt(match[3]) };
}

function compareVersions(a, b) {
    const va = parseVersion(a);
    const vb = parseVersion(b);
    if (!va || !vb) return 0;
    if (va.major !== vb.major) return va.major - vb.major;
    if (va.minor !== vb.minor) return va.minor - vb.minor;
    return va.patch - vb.patch;
}

function checkConsistency(cliVersion, axiosVersion) {
    const issues = [];

    // 找對應的 axios 版本範圍
    const range = AXIOS_RANGES.find(r => {
        return compareVersions(cliVersion, r.cliMin) >= 0 &&
               compareVersions(cliVersion, r.cliMax) <= 0;
    });

    if (range) {
        if (axiosVersion !== range.axiosVer) {
            issues.push({
                severity: 'HIGH',
                message: `CLI version ${cliVersion} should have axios ${range.axiosVer}, but got ${axiosVersion}`,
                expected: range.axiosVer,
                actual: axiosVersion
            });
        }
    } else {
        // CLI 版本不在已知範圍內
        // 如果 > 2.1.80，預期 axios 1.13.6
        if (compareVersions(cliVersion, '2.1.80') >= 0 && axiosVersion !== '1.13.6') {
            issues.push({
                severity: 'MEDIUM',
                message: `CLI version ${cliVersion} (>= 2.1.80) likely expects axios 1.13.6, but got ${axiosVersion}`,
                expected: '1.13.6',
                actual: axiosVersion
            });
        }
    }

    return issues;
}

function main() {
    const args = process.argv.slice(2);

    if (args.includes('--help') || args.length === 0) {
        console.log('Version Consistency Check Tool');
        console.log('');
        console.log('Usage:');
        console.log('  node version-consistency-check.js --cli <version> --axios <version>');
        console.log('  node version-consistency-check.js --headers \'{"user-agent":"..."}\'');
        console.log('  node version-consistency-check.js --dump-map');
        console.log('');
        console.log('Examples:');
        console.log('  node version-consistency-check.js --cli 2.1.81 --axios 1.13.6');
        console.log('  node version-consistency-check.js --cli 2.1.22 --axios 1.13.6');
        console.log('  node version-consistency-check.js --dump-map');
        return;
    }

    if (args.includes('--dump-map')) {
        console.log('Known Version Mapping (from empirical testing):');
        console.log('');
        console.log('Claude Code Version  │ Bundled Axios │ Token UA');
        console.log('─────────────────────┼───────────────┼─────────────────');
        for (const [cc, ax] of Object.entries(VERSION_MAP.axios)) {
            console.log(`${cc.padEnd(20)} │ ${ax.padEnd(13)} │ axios/${ax}`);
        }
        console.log('');
        console.log('Ranges:');
        for (const r of AXIOS_RANGES) {
            console.log(`  CLI ${r.cliMin} ~ ${r.cliMax} → axios/${r.axiosVer}`);
        }
        return;
    }

    let cliVersion, axiosVersion;

    const cliIdx = args.indexOf('--cli');
    const axiosIdx = args.indexOf('--axios');
    const headersIdx = args.indexOf('--headers');

    if (headersIdx >= 0) {
        try {
            const headers = JSON.parse(args[headersIdx + 1]);
            const ua = headers['user-agent'] || headers['User-Agent'] || '';
            const cliMatch = ua.match(/claude-cli\/([0-9.]+)/);
            if (cliMatch) cliVersion = cliMatch[1];

            // 如果有 token UA
            const tokenUa = headers['token-user-agent'] || '';
            const axiosMatch = tokenUa.match(/axios\/([0-9.]+)/);
            if (axiosMatch) axiosVersion = axiosMatch[1];
        } catch (e) {
            console.error('Error parsing headers JSON:', e.message);
            process.exit(1);
        }
    }

    if (cliIdx >= 0) {
        cliVersion = args[cliIdx + 1].replace(/^claude-cli\//, '').replace(/\s.*/, '');
    }
    if (axiosIdx >= 0) {
        axiosVersion = args[axiosIdx + 1].replace(/^axios\//, '');
    }

    if (!cliVersion || !axiosVersion) {
        console.error('Error: both --cli and --axios are required');
        process.exit(1);
    }

    console.log(`Checking: CLI=${cliVersion}, axios=${axiosVersion}`);
    console.log('');

    const issues = checkConsistency(cliVersion, axiosVersion);

    if (issues.length === 0) {
        console.log('✓ Version combination is consistent with known Claude Code releases.');

        // 找確切匹配
        const exact = VERSION_MAP.axios[cliVersion];
        if (exact) {
            console.log(`  Verified: claude-code@${cliVersion} bundles axios ${exact}`);
        }
    } else {
        console.log('✗ Version inconsistency detected:');
        for (const issue of issues) {
            console.log(`  [${issue.severity}] ${issue.message}`);
        }
        console.log('');
        console.log('This may indicate a proxy/relay service that misconfigured its version headers.');
    }
}

main();
