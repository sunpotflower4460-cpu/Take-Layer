import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    // The real-Postgres tests share one throwaway database and TRUNCATE their tables; running test FILES in
    // parallel made them wipe each other's rows mid-test (a false "two winners"). Tests inside a file still run
    // concurrently where they are independent. Total runtime is a few seconds.
    fileParallelism: false,
  },
})
