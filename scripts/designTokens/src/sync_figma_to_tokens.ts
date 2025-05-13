import 'dotenv/config'
import * as fs from 'fs'

import FigmaApi from './figma_api.js'

async function main() {
  if (!process.env.PERSONAL_ACCESS_TOKEN || !process.env.FILE_KEY) {
    throw new Error('PERSONAL_ACCESS_TOKEN and FILE_KEY environemnt variables are required')
  }
  const fileKey = process.env.FILE_KEY

  const api = new FigmaApi(process.env.PERSONAL_ACCESS_TOKEN)
  const publishedVariables = await api.getPublishedVariables(fileKey)
  const localVariables = await api.getLocalVariables(fileKey)

  const fileStyles = await api.getFileStyles(fileKey)
  const fileStylesArray = fileStyles.meta.styles
  const styleNodeIds = fileStylesArray.map((style) => style.node_id)
  const styles = await api.getFileNodes(fileKey, styleNodeIds.join(`,`))

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

  fs.writeFileSync(`${outputDir}/tokens_styles.json`, JSON.stringify(styles, null, 2))
  console.log(`Wrote tokens_styles.json`)

  console.log(`✅ Tokens files have been written to the ${outputDir} directory`)
}

main()
