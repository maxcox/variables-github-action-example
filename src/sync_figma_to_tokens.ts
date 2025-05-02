import 'dotenv/config'
import * as fs from 'fs'

import FigmaApi from './figma_api.js'

import { green } from './utils.js'
import { tokenFilesFromLocalVariables } from './token_export.js'

/**
 * Usage:
 *
 * // Defaults to writing to the tokens_new directory
 * npm run sync-figma-to-tokens
 *
 * // Writes to the specified directory
 * npm run sync-figma-to-tokens -- --output directory_name
 */

async function main() {
  if (!process.env.PERSONAL_ACCESS_TOKEN || !process.env.FILE_KEY) {
    throw new Error('PERSONAL_ACCESS_TOKEN and FILE_KEY environemnt variables are required')
  }
  const fileKey = process.env.FILE_KEY

  const api = new FigmaApi(process.env.PERSONAL_ACCESS_TOKEN)
  const publishedVariables = await api.getPublishedVariables(fileKey)
  const localVariables = await api.getLocalVariables(fileKey)

  const tokensFiles = tokenFilesFromLocalVariables(localVariables)

  let outputDir = 'tokens_new'
  const outputArgIdx = process.argv.indexOf('--output')
  if (outputArgIdx !== -1) {
    outputDir = process.argv[outputArgIdx + 1]
  }

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
  }

  fs.writeFileSync(`${outputDir}/tokens_published.json`, JSON.stringify(publishedVariables, null, 2))
  console.log(`Wrote tokens_published.json`)

  fs.writeFileSync(`${outputDir}/tokens_local.json`, JSON.stringify(localVariables, null, 2))
  console.log(`Wrote tokens_local.json`)

  console.log(green(`✅ Tokens files have been written to the ${outputDir} directory`))
}

main()
