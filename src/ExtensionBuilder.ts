import fs from 'fs';
import util from 'util';
import glob from 'glob';
import child_process from 'child_process';
import path from 'path';

const readFile = util.promisify(fs.readFile);
const writeFile = util.promisify(fs.writeFile);

type ExtensionBuilderOptions = {
    name: string,
    path: string,
    ref: string,
    foswikiLibPath: string,
    releaseString: string,
    outPath: string,
    githubAuthToken: string,
    fontAwesomeNpmAuthToken: string,
    isRootPath: boolean,
    flags: string,
}

class ExtensionBuilder {
    name: string;
    ref: string;
    path: string;
    foswikiLibPath: string;
    releaseString: string;
    outPath: string;
    githubAuthToken: string;
    fontAwesomeNpmAuthToken: string;
    isRootPath: boolean;
    flags: string;
    constructor({name, path, ref, foswikiLibPath, outPath, releaseString, githubAuthToken, isRootPath, flags, fontAwesomeNpmAuthToken}: ExtensionBuilderOptions) {
        this.name = name;
        this.path = path;
        this.ref = ref;
        this.releaseString = releaseString;
        this.foswikiLibPath = foswikiLibPath;
        this.outPath = outPath
        this.githubAuthToken = githubAuthToken;
        this.isRootPath = isRootPath;
        this.flags = flags;
        this.fontAwesomeNpmAuthToken = fontAwesomeNpmAuthToken;
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

        let content = await readFile(pmFile, 'utf8');
        content = this.replaceReleaseString(content);
        content = this.replaceDeprecatedSVNVersionString(content);

        await writeFile(pmFile, content);
    }
    replaceReleaseString(content: string) {
        return content.replace(/^(\s*(?:our\s*)?\$RELEASE\s*=\s*['"]).*(['"]\s*;)/m, `$1${this.releaseString}$2`);
    }
    replaceDeprecatedSVNVersionString(content: string){
        return content.replace(/^(\s*(?:our\s*)?\$VERSION\s*=\s*['"])\$Rev.*(['"]\s*;)/m, `$1${this.releaseString}$2`);
    }
    async getComponentRootPath() {
        const self = this;
        if (self.isRootPath) {
            return self.path;
        }
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
            await this.executeExtensionBuildCommand(componentBuildCommand, { cwd: componentRootPath, env: environment, maxBuffer: 1024 * 500 });
        } catch(reason) {
            throw(new Error(reason));
        }
    }
    async executeExtensionBuildCommand(buildCommand: string, options: child_process.ExecOptions) {
        await new Promise((resolve, reject) => {
            const build = child_process.exec(buildCommand, options);
            if (!build.stdout || !build.stderr) {
                return reject(new Error(`Could not execute '${buildCommand}'!`));
            }
            build.stdout.on('data', (data: string) => console.log(data));
            build.stderr.on('data', (data: string) => console.error(data));
            build.on('error', (err: string) => reject(new Error(err)));
            build.on('close', (code: number) => {
                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`Could not run build. Exit with ${code}`));
                }
            });
        });
    }
    getBuildEnv() {
        const environment = Object.assign({}, process.env);
        environment.FOSWIKI_LIBS = this.foswikiLibPath;
        environment.GITHUB_TOKEN = this.githubAuthToken;
        environment.FONTAWESOME_NPM_AUTH_TOKEN = this.fontAwesomeNpmAuthToken;
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
    async getComponentBuildCommand(){
        const pmFilePath = path.dirname(await this.findExtensionMainFile());
        return `perl ${pmFilePath}/${this.name}/build.pl release ${this.flags}`;
    }
    async deployToOutPath() {
        const componentPath = await this.getComponentRootPath();

        await this.copyFile(componentPath, this.outPath, `${this.name}.tgz`);
        await this.copyFile(componentPath, this.outPath, `${this.name}_installer`);
        await this.copyFile(componentPath, this.outPath, 'metadata.json');
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
