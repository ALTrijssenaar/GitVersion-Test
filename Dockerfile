FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim

# Install Git, PowerShell, and prerequisites in a single layer to minimise
# image size and avoid redundant package index downloads.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git \
       wget \
    && wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/*

# Install the GitVersion CLI as a .NET global tool
RUN dotnet tool install --global GitVersion.Tool

# Expose .NET global tools on PATH and create the short 'gitversion' alias
ENV PATH="${PATH}:/root/.dotnet/tools"
RUN ln -sf /root/.dotnet/tools/dotnet-gitversion /root/.dotnet/tools/gitversion

# Install Pester 5+ for PowerShell testing
RUN pwsh -NoLogo -NoProfile -Command \
    "Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck"

# Set a deterministic git identity so the parent-repo operations succeed.
# Individual test sandboxes override this with their own identity.
RUN git config --global user.email "gitversion-test@example.com" \
    && git config --global user.name "GitVersion Test" \
    && git config --global init.defaultBranch main

WORKDIR /repo
COPY . .

# Bootstrap a git repository so the submodule-based test sandboxes work.
# The sandbox helpers call 'git submodule add' against the parent repo, which
# requires it to be a proper git repository.
RUN git init \
    && git add -A \
    && git commit -m "chore: docker image snapshot"

CMD ["pwsh", "-NoLogo", "-NoProfile", "-File", "RUNME.ps1"]
