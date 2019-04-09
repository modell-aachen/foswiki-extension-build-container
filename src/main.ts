// const BuildService = require("./BuildService");

import dotenv from 'dotenv';
import fs, { write } from 'fs';
import axios from 'axios';
import path from 'path';
import unzip from 'unzip';
import { ExtensionBuilder } from './ExtensionBuilder';

dotenv.config();
const githubOrganization = process.env.GITHUB_ORGANIZATION || "";
const repository = process.env.GITHUB_REPOSITORY || "";
const ref = process.env.GITHUB_REF || "";
const githubAuthToken = process.env.GITHUB_AUTH_TOKEN || "";
const buildPath = process.env.BUILD_PATH || "";
const deployPath = process.env.DEPLOY_PATH || "";
const foswikiLibPath = process.env.FOSWIKI_LIBS || "";

const archiveDownloadUrl = `https://api.github.com/repos/${githubOrganization}/${repository}/zipball/${ref}`;
const archiveDownloadPath = path.resolve(buildPath, 'archive.zip');

const downloadFile = async (url: string, path:string) => {
    const response = await axios({
        url,
        method: 'GET',
        responseType: 'stream',
        headers: {'Authorization': `token ${githubAuthToken}`},
    });

    const writer = fs.createWriteStream(path);

    response.data.pipe(writer);

    return new Promise((resolve, reject) => {
        writer.on('finish', resolve);
        writer.on('error', reject);
    });
}

const unzipArchive = async (archivePath: string, outputPath: string) => {
    const archiveReader = fs.createReadStream(archivePath);
    const unzipper = unzip.Extract({path: outputPath});
    archiveReader.pipe(unzipper);
    return new Promise((resolve, reject) => {
        unzipper.on('close', resolve);
        unzipper.on('error', reject);
    });
}

const main = async () => {
    await downloadFile(archiveDownloadUrl, archiveDownloadPath);
    await unzipArchive(archiveDownloadPath, buildPath);

    const extensionBuilder = new ExtensionBuilder({
        name: repository,
        path: buildPath,
        ref: ref,
        foswikiLibPath: foswikiLibPath,
        outPath: deployPath,
    });
    await extensionBuilder.build();
}

main().then(console.log, console.log);
