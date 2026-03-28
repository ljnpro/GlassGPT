/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      from: {},
      to: {
        circular: true,
      },
    },
    {
      name: 'contracts-no-runtime-imports',
      severity: 'error',
      from: {
        path: '^packages/backend-contracts/src',
      },
      to: {
        path: '^(packages/backend-infra|services/backend)/',
      },
    },
    {
      name: 'infra-no-backend-runtime',
      severity: 'error',
      from: {
        path: '^packages/backend-infra/src',
      },
      to: {
        path: '^services/backend/src',
      },
    },
    {
      name: 'backend-runtime-no-infra-imports',
      severity: 'error',
      from: {
        path: '^services/backend/src',
      },
      to: {
        path: '^packages/backend-infra/src',
      },
    },
    {
      name: 'domain-no-outward-imports',
      severity: 'error',
      from: {
        path: '^services/backend/src/domain',
      },
      to: {
        path: '^services/backend/src/(application|adapters|http|workflows)',
      },
    },
    {
      name: 'application-no-transport-imports',
      severity: 'error',
      from: {
        path: '^services/backend/src/application',
      },
      to: {
        path: '^services/backend/src/(adapters|http|workflows)',
      },
    },
    {
      name: 'http-no-adapter-bypass',
      severity: 'error',
      from: {
        path: '^services/backend/src/http',
      },
      to: {
        path: '^services/backend/src/adapters',
      },
    },
    {
      name: 'workflows-no-http-imports',
      severity: 'error',
      from: {
        path: '^services/backend/src/workflows',
      },
      to: {
        path: '^services/backend/src/http',
      },
    },
  ],
  options: {
    doNotFollow: {
      path: 'node_modules',
    },
    exclude: '(^|/)(dist|generated)/',
    tsPreCompilationDeps: true,
  },
};
