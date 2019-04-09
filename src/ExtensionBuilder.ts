import fs from 'fs';
// import del from 'del';
import util from 'util';
import glob from 'glob';
import child_process from 'child_process';
import path from 'path';
const exec = util.promisify(child_process.exec);
// const lodash = require('lodash');
// const mkdirp = util.promisify(require('mkdirp'));
// const sanitizeFilename = require("sanitize-filename");
const access = util.promisify(fs.access);

const readFile = util.promisify(fs.readFile);
const writeFile = util.promisify(fs.writeFile);

type ExtensionBuilderOptions = {
    name: string,
    path: string,
    ref: string,
    foswikiLibPath: string,
    outPath: string,
}

class ExtensionBuilder {
    name: string;
    ref: string;
    path: string;
    foswikiLibPath: string;
    outPath: string
    constructor({name, path, ref, foswikiLibPath, outPath}: ExtensionBuilderOptions) {
        this.name = name;
        this.path = path;
        this.ref = ref;
        this.foswikiLibPath = foswikiLibPath;
        this.outPath = outPath
    }
    async build() {
        await this.prepareComponentForBuild();
        await this.buildPreparedComponent();
        await this.deployToOutPath();
    }

    async prepareComponentForBuild() {
        await this.rewriteReleaseAndVersion();
    }
    async rewriteReleaseAndVersion(){
        const pmFile = await this.findExtensionMainFile();
        let replacementString = `$1${this.releaseString()}$2`;

        let content = await readFile(pmFile, 'utf8');

        // change RELEASE string in .pm file
        content = content.replace(/^(\s*(?:our\s*)?\$RELEASE\s*=\s*['"]).*(['"]\s*;)/m, replacementString);

        // filter deprecated SVN Version strings
        content = content.replace(/^(\s*(?:our\s*)?\$VERSION\s*=\s*['"])\$Rev.*(['"]\s*;)/m, replacementString);

        await writeFile(pmFile, content);
    }
    async getComponentRootPath() {
        const self = this;
        return new Promise<string>((resolve, reject) => {
            glob(`${self.path}/*/`, (err, matches) => {
                if(err){
                    reject(err);
                }
                resolve(matches[0]);
            });
        });    }
    async buildPreparedComponent() {
        const componentBuildCommand = await this.getComponentBuildCommand();
        const componentRootPath = await this.getComponentRootPath();

        try {
            const environment = this.getBuildEnv();
            await this.executeExtensionBuildCommand(componentBuildCommand, { cwd: componentRootPath, env: environment });
        } catch(reason) {
            throw(new Error(reason));
        }
    }
    async executeExtensionBuildCommand(buildCommand: string, options: child_process.ExecOptions) {
        await exec(buildCommand, options);
    }
    getBuildEnv() {
        const environment = Object.assign({}, process.env);
        environment.FOSWIKI_LIBS = this.foswikiLibPath;
        delete environment.NODE_ENV; // this might be set to 'production', confusing the build process
        return environment;
    }
    async findExtensionMainFile() {
        const self = this;
        return new Promise<string>((resolve, reject) => {
            glob(`${self.path}/**/${self.name}.pm`, (err, matches) => {
                if(err){
                    reject(err);
                }
                resolve(matches[0]);
            });
        });
    }
    async getComponentPmFilePath() {
        let pmFilePath = this.findExtensionMainFile();
        return pmFilePath;
    }

    async getComponentBuildCommand(){
        const pmFilePath = path.dirname(await this.findExtensionMainFile());
        return `perl ${pmFilePath}/${this.name}/build.pl release`;
    }

    async deployToOutPath() {
        const componentPath = await this.getComponentRootPath();

        await this.copyFile(componentPath, this.outPath, `${this.name}.tgz`);
        await this.copyFile(componentPath, this.outPath, `${this.name}_installer`);
        await this.copyFile(componentPath, this.outPath, `${this.name}.txt`);
    }

    releaseString() {
        if(/q\d+.\d+.\d+/.test(this.ref)){
            return this.ref.substr(1);
        } else {
            return new Date().toISOString();
        }
    }
    async copyFile(srcdir: string, dstdir: string, file: string) {
        return new Promise((resolve, reject) => {
            let src = path.resolve(srcdir, file);
            let dst = path.resolve(dstdir, file);
            let read = fs.createReadStream(src);
            read.on('error', () => {
                reject(new Error('Could not read file for copying: ' + src));
            });
            let write = fs.createWriteStream(dst);
            write.on('error', () => {
                reject(new Error('Could not open target for copying: ' + dst));
            });
            write.on('finish', () => {
                resolve();
            });
            read.pipe(write);
        });
    };
}

export { ExtensionBuilder };
