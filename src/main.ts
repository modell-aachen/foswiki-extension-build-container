import dotenv from 'dotenv';
import fs from 'fs';
import axios from 'axios';
import path from 'path';
import { ExtensionBuilder } from './ExtensionBuilder';
import tar from 'tar';
import { execSync } from 'child_process';

dotenv.config();
const githubOrganization = process.env.GITHUB_ORGANIZATION || "";
const fontAwesomeNpmAuthToken = process.env.FONTAWESOME_NPM_AUTH_TOKEN || "";
const repository = process.env.GITHUB_REPOSITORY || "";
const ref = process.env.GITHUB_REF || "";
const githubAuthToken = process.env.GITHUB_AUTH_TOKEN || "";
const buildPath = process.env.BUILD_PATH || "";
const deployPath = process.env.DEPLOY_PATH || "";
const releaseString = process.env.RELEASE_STRING || "";
const hasLocalRepository = !!process.env.HAS_LOCAL_REPOSITORY;

const archiveDownloadUrl = `https://api.github.com/repos/${githubOrganization}/${repository}/tarball/${ref}`;
const archiveDownloadPath = path.resolve(buildPath, 'archive.tar.gz');

const downloadSourceArchive = async (url: string, path:string) => {
    let response;
    try {
        response = await axios({
            url,
            method: 'GET',
            responseType: 'stream',
            headers: {'Authorization': `token ${githubAuthToken}`},
        });
    } catch(error) {
        throw new Error(`Failed downloading source archive from Github: ${error.response.statusText}`);
    }

    const writer = fs.createWriteStream(path);

    response.data.pipe(writer);

    return new Promise((resolve, reject) => {
        writer.on('finish', resolve);
        writer.on('error', reject);
    });
}

const unzipSourceArchive = async (archivePath: string, outputPath: string) => {
    const archiveReader = fs.createReadStream(archivePath);
    const unzipper = tar.x({cwd: outputPath, });
    archiveReader.pipe(unzipper);
    return new Promise((resolve, reject) => {
        unzipper.on('close', resolve);
        unzipper.on('error', reject);
    });
}

const copyRepoTo = (path: string) => {
    execSync(`cp -rf /repo ${path}`);
    execSync(`rm -rf ${path}/repo/.git`);
    execSync(`find -L ${path} -type l -delete`);
}

const main = async () => {
    if (hasLocalRepository) {
        copyRepoTo(buildPath);
    } else {
        console.info(`Starting: ${githubOrganization}/${repository} on ${ref}`);
        console.info("Downloading source archive from Github...");
        await downloadSourceArchive(archiveDownloadUrl, archiveDownloadPath);
        console.info("Unzipping...");
        await unzipSourceArchive(archiveDownloadPath, buildPath);
    }

    const extensionBuilder = new ExtensionBuilder({
        name: repository,
        path: buildPath,
        ref: ref,
        releaseString: releaseString,
        outPath: deployPath,
        githubAuthToken: githubAuthToken,
        fontAwesomeNpmAuthToken,
    });
    console.info("Creating build...");
    await extensionBuilder.build();
}

main().then(() => {
    console.info(`Build succeeded and deployed to ${deployPath}`);
}, (err) => {
    console.error(err);
    process.exit(1);
});
