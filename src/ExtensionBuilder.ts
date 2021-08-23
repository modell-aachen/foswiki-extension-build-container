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
    releaseString: string,
    outPath: string,
    githubAuthToken: string,
    fontAwesomeNpmAuthToken: string,
}

class ExtensionBuilder {
    name: string;
    ref: string;
    path: string;
    releaseString: string;
    outPath: string;
    githubAuthToken: string;
    fontAwesomeNpmAuthToken: string;
    constructor({name, path, ref, outPath, releaseString, githubAuthToken, fontAwesomeNpmAuthToken}: ExtensionBuilderOptions) {
        this.name = name;
        this.path = path;
        this.ref = ref;
        this.releaseString = releaseString;
        this.outPath = outPath
        this.githubAuthToken = githubAuthToken;
        this.fontAwesomeNpmAuthToken = fontAwesomeNpmAuthToken;
    }
    async build() {
        await this.buildPreparedComponent();
        await this.deployToOutPath();
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
        try {
            await this.executeExtensionBuildCommand(`./build ${this.releaseString}`, {
                cwd: await this.getComponentRootPath(),
                env: this.getBuildEnv(),
                maxBuffer: 1024 * 500,
            });
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
        environment.GITHUB_TOKEN = this.githubAuthToken;
        environment.FONTAWESOME_NPM_AUTH_TOKEN = this.fontAwesomeNpmAuthToken;
        delete environment.NODE_ENV; // this might be set to 'production', confusing the build process
        return environment;
    }
    async deployToOutPath() {
        const componentPath = await this.getComponentRootPath();

        await this.copyFile(componentPath, this.outPath, `${this.name}.tgz`);
        fs.writeFileSync(`${this.outPath}/${this.name}_installer`, '');
        fs.writeFileSync(`${this.outPath}/metadata.json`, this.metadata());
    }
    metadata() {
        return JSON.stringify({
            description : "Q.wiki",
            version: "1.0",
            release: this.releaseString,
            date: (new Date()).toISOString(),
            dependencies: [],
        }, null, 2);
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
